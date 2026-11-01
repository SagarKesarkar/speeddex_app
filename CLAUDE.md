
# Flutter UI Engineering Rules

## Goal
Recreate provided screenshots and Figma designs as closely as
practical using clean, maintainable Flutter code.

## Before implementation
- Inspect the existing project, theme, assets, reference and dependencies.
- Study every provided reference screenshot carefully.
- Identify screen dimensions, safe areas, spacing, typography,
  colors, corner radii, shadows, icons and image cropping.
- Preserve the existing architecture unless a change is necessary.

## UI implementation
- Use reusable widgets and a consistent design system.
- Prefer theme tokens over repeated hard-coded values.
- Use LayoutBuilder and appropriate responsive constraints.
- Support small phones, large phones and tablet layouts.
- Respect SafeArea, scrolling, keyboard insets and text scaling.
- Use real assets and suitable icons; avoid placeholder emoji
  when the design specifies icons or illustrations.
- Implement visible interactions, loading states, empty states,
  errors and accessibility semantics.

## Screenshot-driven workflow
1. Implement the smallest useful screen or component.
2. Run the app on an Android emulator.
3. Capture a screenshot at the reference dimensions.
4. Compare layout, spacing, typography, colors and image crops.
5. Fix the most noticeable mismatches.
6. Repeat until the screen is visually consistent.
7. Test scrolling, interactions and different screen sizes.

## Quality gates
- Run dart format on changed Dart files.
- Run flutter analyze and relevant widget tests.
- Fix new errors and warnings where practical.
- Do not claim visual verification unless screenshots were
  actually captured and inspected.
- Do not replace existing functionality just to match a mockup.
