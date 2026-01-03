use tauri::{
    menu::{Menu, MenuBuilder, MenuItem, PredefinedMenuItem, Submenu, SubmenuBuilder},
    AppHandle, Runtime,
};

/// Build the system tray menu
pub fn build_tray_menu<R: Runtime>(app: &AppHandle<R>) -> Result<Menu<R>, tauri::Error> {
    let show_item = MenuItem::with_id(app, "show", "Show RepoBar", true, None::<&str>)?;
    let settings_item = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let refresh_item = MenuItem::with_id(app, "refresh", "Refresh", true, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit RepoBar", true, None::<&str>)?;

    let menu = MenuBuilder::new(app)
        .item(&show_item)
        .separator()
        .item(&refresh_item)
        .separator()
        .item(&settings_item)
        .separator()
        .item(&quit_item)
        .build()?;

    Ok(menu)
}

/// Build a dynamic repositories submenu (for future use)
pub fn build_repositories_submenu<R: Runtime>(
    app: &AppHandle<R>,
    repos: Vec<String>,
) -> Result<Submenu<R>, tauri::Error> {
    let mut submenu_builder = SubmenuBuilder::new(app, "Repositories");

    if repos.is_empty() {
        let no_repos = MenuItem::with_id(app, "no_repos", "No repositories", false, None::<&str>)?;
        submenu_builder = submenu_builder.item(&no_repos);
    } else {
        for (idx, repo) in repos.iter().enumerate() {
            let id = format!("repo_{}", idx);
            let item = MenuItem::with_id(app, id, repo, true, None::<&str>)?;
            submenu_builder = submenu_builder.item(&item);
        }
    }

    submenu_builder.build()
}
