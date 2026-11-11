# example-app

- Runs in docker: use `docker exec -w /app php php` for any PHP CLI call, never the host php (2026-11-02, claude)
- Schema changes go through `php command migrate`; deploy runs it automatically, so never ALTER by hand (2026-11-03, codex)
- Admin date pickers render a hidden `<name>` input plus a visible `text_<name>` input; tests must fill the visible one and blur (2026-11-11, claude)
- Preview deploys: `https://<branch>.preview.example.com`, basic auth via PREVIEW_USER/PREVIEW_PASS; `/admin/` 404s on previews, use `/admin/index.php` (2026-11-11, claude)
