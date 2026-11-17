# Directives du Projet LaunchPad

## Incrémentation Automatique de Version

À **chaque modification** apportée à l'application (fonctionnalité, correctif ou ajustement visuel), il est obligatoire d'incrémenter automatiquement le numéro de version (`vX.Y.Z` → `vX.Y.(Z+1)`), de mettre à jour `MARKETING_VERSION` dans `LaunchPad.xcodeproj/project.pbxproj`, `AdminTestCenterView.swift` et `version.json`, de recompiler le build Release, de régénérer les archives (`LaunchPad.dmg`, `LaunchPad-vX.Y.Z.dmg`, `LaunchPad-vX.Y.Z.zip`) et de publier la nouvelle version (tag + release GitHub) selon le modèle ci-dessous.

## Format Obligatoire des Releases GitHub & Notes de Version

À chaque création d'une nouvelle version (release GitHub, tag, annonce de mise à jour), les notes de version doivent **strictement** respecter le modèle suivant (conforme à l'affichage Discord et in-app) :

### Modèle :

```markdown
### 🚀 Nouveautés de LaunchPad vX.Y.Z

- [EMOJI] **[Titre de la fonctionnalité ou amélioration]** : [Description claire, attrayante et précise de l'apport pour l'utilisateur en 1 à 2 lignes].
- [EMOJI] **[Deuxième point fort]** : [Explication concise].
- [EMOJI] **[Troisième point fort]** : [Explication concise].
- [EMOJI] **[Quatrième point fort]** : [Explication concise].
- [EMOJI] **[Cinquième point fort]** : [Explication concise].
```

### Règles de rédaction :
1. **Titre de la release GitHub** : Toujours `LaunchPad vX.Y.Z`.
2. **En-tête** : Toujours `### 🚀 Nouveautés de LaunchPad vX.Y.Z`.
3. **Puces** : Utiliser des tirets `- ` avec un emoji représentatif immédiatement suivi du titre en gras `**...**` puis d'un deux-points ` : ` et de l'explication.
4. **Style** : Synthétique, orienté bénéfice utilisateur, élégant et soigné.
5. **À bannir** : Les sous-listes techniques type *"Avant / Après"*, les blocs de code verbeux ou les séparateurs horizontaux `---` qui dégradent l'affichage des embeds Discord et des fenêtres de mise à jour in-app.
