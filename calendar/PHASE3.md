# Phase 3 — Board V1 : refonte + intégration calendrier

Refonte du board kanban (resté au stade Phase 2) pour atteindre une vraie V1 : le
calendrier dit *quand*, le board dit *quoi faire*, et les deux sont reliés. Livré en
4 sous-phases (chacune compilée/testée/installée séparément). Plugin `calendar`
v0.6.0 → v0.7.0 ; backend `calsync` (board + cli + daemon).

## 3A — Refonte visuelle (plugin seul)
- Colonnes en îlots `NBox forceOpaque` (mSurfaceVariant), pastille d'accent par
  colonne (`columnAccent`, cycle mPrimary/Secondary/Tertiary), pill compteur, bordure
  mPrimary au survol-drag.
- Cartes riches : hover (`mHover`), **chip échéance relatif** (`dueLabel`/`dueColor`/
  `parseDue` : « Demain », « Dans 3 j », « En retard » en mError), barre de progression.
- Drag-drop avec **ligne d'insertion** (`computeDrop` → `dropBeforeId`, marqueur 2px).
- Éditeur : migration `onEditingFinished` → `onTextChanged` (bug de capture connu) ;
  échéance en **date + heure** (réutilise `buildISO`/`partsToDue`).

## 3B — Étiquettes + sous-tâches + filtres
- **Backend** (`board.go`/`cli/board.go`) : `Board.Labels []Label{ID,Name,Color}`,
  `Card.Labels []string`, `Card.Checklist []ChecklistItem{ID,Text,Done}`. Progression
  **dérivée de la checklist** (`syncProgress` : done/total) quand elle existe. CLI
  `label add|rm|list`, `check add|toggle|rm`, `--labels` sur add/update-card.
- **Plugin** : chips d'étiquettes colorés (tokens de thème via `labelColor`), badge
  checklist `☑ n/m`, éditeur de checklist live (NCheckbox), barre de filtre
  (recherche + chips priorité/labels), overlay gestionnaire d'étiquettes.

## 3C — Planification & intégration calendrier
- **Backend** : `Card.Schedule *TimeBlock{Start,End}` (bloc local) ; CLI
  `board schedule <id> --start --end [--real [--calendar-id]]` (mode `--real` crée un
  vrai event Google via `newSyncer`/`AddEvent`, comme `event add`, et le lie via
  `CalendarEventID`) et `board unschedule`.
- **Plugin** : section « Planifier » (toggle bloc local ⟷ event Google, date/heure +
  durée NSpinBox). `Main.qml` dérive `taskBlocksOnDay` (blocs locaux event-like),
  `tasksDueOnDay` (échéances) et `eventLinkedTaskId`. Rendu : blocs de tâches packés
  dans la grille jour/semaine (style outline « ☑ »), échéances en chips dans le
  bandeau all-day (jour/semaine) et en cellule (mois), event Google lié marqué « ☑ ».
  Clic sur une tâche depuis le calendrier → `openCardById` (cross-tab).

## 3D — Rappels d'échéance + tâches récurrentes
- **Daemon** (`reminders.go`) : `planTaskReminders` + `activeDueCards` (cartes avec
  Due, non terminées) réutilisent les offsets/état des rappels d'événements (clés
  `card:<id>|<due>|<offset>`), titres « Échéance … ». Due date-only → ancré à 09:00.
  ⚠️ Piloté par le **même réglage rappels** que les events (General tab) : désactivé
  si les rappels d'événements le sont.
- **Backend** : `Card.Recurrence *CardRecur{Freq,Interval}` + `Card.CompletedAt`.
  `maybeRegen` : quand une carte récurrente passe en *Done* (colonne nommée « Done »
  ou progress ≥ 100), elle est stampée `CompletedAt` et une copie fraîche est créée en
  1re colonne (Due avancé via `advanceDue`, progression/checklist remises à zéro).
  Branché dans `UpdateCard`/`MoveCard`. CLI `--recurrence daily|weekly|monthly[:N]`
  (`none` pour retirer).
- **Plugin** : sélecteur récurrence (combo + intervalle NSpinBox), badges 🔁 / 📅.

## Vérification
- `go test ./... -race` vert (board/cli/daemon tests ajoutés) ; backend `make install`
  + `systemctl --user restart calsync`. CLI live vérifié : labels/checklist (progression
  0→50), schedule local set/clear, **récurrence regen** (Due +1 semaine, copie en todo).
  `--real` non testé live (mirroir exact de `event add`).
- Plugin : accolades équilibrées + parité i18n fr/en. `qmllint` inexploitable hors
  compositeur (alias `qs.*`). **Nécessite git push + maj plugin Noctalia + RELOG.**
- Champs `board.json` additifs (`omitempty`) → rétro-compatibles, pas de `sync --full`.

## Reste possible (post-V1)
Picker mini-mois graphique ; suppression auto de l'event Google lié au unschedule ;
réglage de rappels d'échéance distinct des events ; dépendances entre tâches.
