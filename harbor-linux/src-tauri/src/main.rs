//!
//! Harbor Linux - Platform Services
//!
//! This module provides platform-specific implementations for Linux
//! using Tauri and the platform abstraction layer from HarborCore.
//!

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

// Learn more about Tauri commands at https://tauri.app/v2/guides/features/command
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Harbor Linux!", name)
}

#[tauri::command]
async fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tauri::command]
async fn get_platform() -> String {
    std::env::consts::OS.to_string()
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![greet, get_version, get_platform])
        .run(tauri::generate_context!())
        .expect("error while running Harbor application");
}
