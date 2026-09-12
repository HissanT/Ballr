from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset

from .ball_tracker_juggle_dataset import labeled_records, load_manifest, manifest_path
from .ball_tracker_juggling import (
    FEATURE_NAMES,
    JUGGLE_EVENT_MODEL_CLASSES,
    JuggleEventSequenceModel,
)


LABEL_TO_INDEX = {label: index for index, label in enumerate(JUGGLE_EVENT_MODEL_CLASSES)}


@dataclass(frozen=True)
class _Example:
    features_path: Path
    label_index: int


class _WindowDataset(Dataset):
    def __init__(self, examples: list[_Example]) -> None:
        self._examples = examples

    def __len__(self) -> int:
        return len(self._examples)

    def __getitem__(self, index: int):
        example = self._examples[index]
        payload = np.load(example.features_path)
        features = payload["feature_window"].astype(np.float32)
        return torch.from_numpy(features), torch.tensor(example.label_index, dtype=torch.long)


def _split_examples(records, root: Path, val_ratio: float) -> tuple[list[_Example], list[_Example]]:
    sessions = sorted({record.session_name for record in records})
    if len(sessions) >= 2:
        val_count = max(1, int(round(len(sessions) * val_ratio)))
        val_sessions = set(sessions[-val_count:])
        train_records = [record for record in records if record.session_name not in val_sessions]
        val_records = [record for record in records if record.session_name in val_sessions]
    else:
        cutoff = max(1, int(round(len(records) * (1.0 - val_ratio))))
        train_records = records[:cutoff]
        val_records = records[cutoff:]

    train_examples = [
        _Example(root / record.features_relpath, LABEL_TO_INDEX[record.training_event_label])
        for record in train_records
    ]
    val_examples = [
        _Example(root / record.features_relpath, LABEL_TO_INDEX[record.training_event_label])
        for record in val_records
    ]
    return train_examples, val_examples


def _accuracy(model, loader: DataLoader, device: str) -> tuple[float, float]:
    model.eval()
    total = 0
    correct = 0
    losses: list[float] = []
    criterion = nn.CrossEntropyLoss()
    with torch.no_grad():
        for features, labels in loader:
            features = features.to(device)
            labels = labels.to(device)
            logits = model(features)
            loss = criterion(logits, labels)
            losses.append(float(loss.item()))
            predictions = torch.argmax(logits, dim=1)
            correct += int((predictions == labels).sum().item())
            total += int(labels.numel())
    if total == 0:
        return 0.0, 0.0
    return correct / total, sum(losses) / max(len(losses), 1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a GRU juggle event classifier")
    parser.add_argument("--root", required=True, help="Reviewed candidate root containing manifest.jsonl")
    parser.add_argument("--output", required=True, help="Checkpoint output path")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--hidden-size", type=int, default=48)
    parser.add_argument("--num-layers", type=int, default=2)
    parser.add_argument("--dropout", type=float, default=0.20)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--val-ratio", type=float, default=0.20)
    args = parser.parse_args()

    root = Path(args.root)
    records = labeled_records(load_manifest(manifest_path(root)))
    if len(records) < 10:
        raise SystemExit("Need at least 10 labeled candidates to train a model.")

    train_examples, val_examples = _split_examples(records, root, args.val_ratio)
    if not train_examples or not val_examples:
        raise SystemExit("Training and validation splits must both be non-empty.")

    train_dataset = _WindowDataset(train_examples)
    val_dataset = _WindowDataset(val_examples)
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = JuggleEventSequenceModel(
        input_size=len(FEATURE_NAMES),
        hidden_size=args.hidden_size,
        num_layers=args.num_layers,
        dropout=args.dropout,
        output_size=len(JUGGLE_EVENT_MODEL_CLASSES),
    ).to(device)

    label_counts = Counter(example.label_index for example in train_examples)
    class_weights = torch.tensor(
        [
            len(train_examples) / max(label_counts.get(index, 1), 1)
            for index in range(len(JUGGLE_EVENT_MODEL_CLASSES))
        ],
        dtype=torch.float32,
        device=device,
    )
    criterion = nn.CrossEntropyLoss(weight=class_weights)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate)

    best_val_acc = -1.0
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    for epoch in range(1, args.epochs + 1):
        model.train()
        epoch_loss = 0.0
        batches = 0
        for features, labels in train_loader:
            features = features.to(device)
            labels = labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(features)
            loss = criterion(logits, labels)
            loss.backward()
            optimizer.step()
            epoch_loss += float(loss.item())
            batches += 1

        train_acc, _train_eval_loss = _accuracy(model, train_loader, device)
        val_acc, val_loss = _accuracy(model, val_loader, device)
        print(
            f"epoch={epoch} train_loss={epoch_loss / max(batches, 1):.4f} "
            f"train_acc={train_acc:.4f} val_loss={val_loss:.4f} val_acc={val_acc:.4f}"
        )

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(
                {
                    "state_dict": model.state_dict(),
                    "feature_names": FEATURE_NAMES,
                    "classes": list(JUGGLE_EVENT_MODEL_CLASSES),
                    "hidden_size": args.hidden_size,
                    "num_layers": args.num_layers,
                    "dropout": args.dropout,
                },
                output_path,
            )

    print(f"Best validation accuracy: {best_val_acc:.4f}")
    print(f"Saved checkpoint to '{output_path}'.")


if __name__ == "__main__":
    main()
