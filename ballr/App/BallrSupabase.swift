import Foundation
import Supabase

enum BallrSupabase {
    static let projectURL = URL(string: "https://bvpyyzusonnounvlgxse.supabase.co")!

    // Safe for client apps. Database access must still be protected by RLS policies.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ2cHl5enVzb25ub3VudmxneHNlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NDcyMDgsImV4cCI6MjA5MzMyMzIwOH0.EO6q0FdLNp2YD_CmHM3q_V1A_y_ErGvcW2gtFs8jldc"

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey
    )
}
