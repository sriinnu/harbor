// Prevents additional console window on Windows in release mode
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod auth;
mod commands;
mod platform;
mod tray;

use commands::{auth::AuthState, settings::SettingsState};
use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            // Initialize system tray
            let _ = tray::init_tray(app.handle());

            // Hide main window initially (system tray app)
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.hide();
            }

            Ok(())
        })
        .manage(AuthState::new())
        .manage(SettingsState::new().expect("Failed to initialize settings"))
        .invoke_handler(tauri::generate_handler![
            // Auth commands
            commands::auth::start_oauth_login,
            commands::auth::load_oauth_tokens,
            commands::auth::load_client_credentials,
            commands::auth::logout,
            commands::auth::is_authenticated,
            // Settings commands
            commands::settings::load_settings,
            commands::settings::save_settings,
            commands::settings::reset_settings,
            // Git commands
            commands::git::locate_git,
            commands::git::get_executable_version,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
