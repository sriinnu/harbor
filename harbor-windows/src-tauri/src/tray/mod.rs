pub mod menu;

use menu::build_tray_menu;
use tauri::{
    menu::{Menu, MenuEvent},
    tray::{TrayIcon, TrayIconBuilder},
    AppHandle, Manager, Runtime,
};

/// Initialize the system tray
pub fn init_tray<R: Runtime>(app: &AppHandle<R>) -> Result<TrayIcon<R>, tauri::Error> {
    let menu = build_tray_menu(app)?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .on_menu_event(handle_menu_event)
        .tooltip("RepoBar")
        .build(app)
}

/// Handle tray menu events
fn handle_menu_event<R: Runtime>(app: &AppHandle<R>, event: MenuEvent) {
    match event.id().as_ref() {
        "show" => {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
        "settings" => {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
                // Emit event to navigate to settings
                let _ = window.emit("navigate", "settings");
            }
        }
        "refresh" => {
            // Emit refresh event to frontend
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.emit("refresh", ());
            }
        }
        "quit" => {
            app.exit(0);
        }
        _ => {}
    }
}

/// Update tray icon (for future use - e.g., showing notification badge)
pub fn update_tray_icon<R: Runtime>(
    _app: &AppHandle<R>,
    _icon_path: &str,
) -> Result<(), tauri::Error> {
    // Future implementation for updating tray icon
    Ok(())
}
