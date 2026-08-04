# Conference V1 Implementation Checklist

## Phase 0: Baseline (Done)
- [x] Local DB credentials validated.
- [x] Local conference section CRUD route sanity-tested.
- [x] Fixed duplicate Add Section action in conference UI.

## Phase 1: Sections Workflow (In Progress)
- [x] Add `conference_sections` status/archive schema migration.
- [x] Add backend section archive endpoint.
- [x] Add backend section restore endpoint.
- [x] Add backend section reorder endpoint.
- [x] Switch delete behavior to archive-first.
- [x] Include section status metadata in conference response.
- [x] Add section status chip in UI.
- [x] Add UI archive/restore actions.
- [x] Add drag-drop reorder in UI.
- [x] Run migration on local DB and verify app behavior.
- [x] Validate endpoint contracts via curl (archive/restore/reorder).

## Phase 2: Attachments (Next)
- [x] Create `conference_section_attachments` table migration.
- [x] Implement presign endpoint.
- [x] Implement attachment create/list/reorder/archive/restore endpoints.
- [x] Add S3 upload config + validation (type/size).
- [x] Build section attachment UI (images + docs).
- [ ] Add thumbnail flow for images.

Phase 2 notes:
- Presign is currently running in mock mode (`ATTACHMENTS_PRESIGN_MODE=mock`) for local development.
- Real signed URL generation wiring is still required before production rollout.

## Phase 3: Status Workflow + Polish
- [ ] Add editable section status field in edit dialog.
- [ ] Add filtered section views by status.
- [ ] UX polish and responsive behavior checks.
- [ ] Audit log verification for all new section actions.

## Phase 4: Notifications (Deferred)
- [ ] Notification design review.
- [ ] Endpoint + queue strategy.
- [ ] UI trigger and templates.

## Validation Matrix
- [ ] Local: permissions matrix for read/edit/archive/restore/reorder.
- [ ] Local: migration idempotency check.
- [ ] AWS: route parity check.
- [ ] AWS: DB migration rollout check.
- [ ] Regression pass on conference overview + ideas.
