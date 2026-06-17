---
name: Campus Bite
colors:
  surface: '#f8f9fa'
  surface-dim: '#d9dadb'
  surface-bright: '#f8f9fa'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f4f5'
  surface-container: '#edeeef'
  surface-container-high: '#e7e8e9'
  surface-container-highest: '#e1e3e4'
  on-surface: '#191c1d'
  on-surface-variant: '#40493d'
  inverse-surface: '#2e3132'
  inverse-on-surface: '#f0f1f2'
  outline: '#707a6c'
  outline-variant: '#bfcaba'
  surface-tint: '#1b6d24'
  primary: '#0d631b'
  on-primary: '#ffffff'
  primary-container: '#2e7d32'
  on-primary-container: '#cbffc2'
  inverse-primary: '#88d982'
  secondary: '#8f4e00'
  on-secondary: '#ffffff'
  secondary-container: '#ff8f06'
  on-secondary-container: '#623300'
  tertiary: '#00569f'
  on-tertiary: '#ffffff'
  tertiary-container: '#006eca'
  on-tertiary-container: '#ebf1ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#a3f69c'
  primary-fixed-dim: '#88d982'
  on-primary-fixed: '#002204'
  on-primary-fixed-variant: '#005312'
  secondary-fixed: '#ffdcc2'
  secondary-fixed-dim: '#ffb77b'
  on-secondary-fixed: '#2e1500'
  on-secondary-fixed-variant: '#6d3a00'
  tertiary-fixed: '#d4e3ff'
  tertiary-fixed-dim: '#a5c8ff'
  on-tertiary-fixed: '#001c3a'
  on-tertiary-fixed-variant: '#004786'
  background: '#f8f9fa'
  on-background: '#191c1d'
  surface-variant: '#e1e3e4'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 57px
    fontWeight: '700'
    lineHeight: 64px
    letterSpacing: -0.25px
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-md:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  headline-sm:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '500'
    lineHeight: 28px
  title-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
    letterSpacing: 0.15px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0.5px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0.25px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.1px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.5px
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  container-margin: 16px
  gutter: 16px
---

## Brand & Style
The design system is crafted for the energetic and fast-paced university environment. It balances the efficiency of a utility app with the appetizing appeal of a food service. The brand personality is **fresh, dependable, and efficient**, focusing on reducing cognitive load for students between classes.

The visual style follows **Modern Minimalism** with a **Material Design 3 (M3)** foundation. It utilizes a container-based architecture (cards) to group information logically, paired with high-quality imagery to stimulate appetite. The emotional response is one of "effortless nourishment"—making the process of finding and ordering food the simplest part of a student's day.

## Colors
The palette is derived from fresh ingredients and the vibrant energy of campus life.
- **Primary (Fresh Green):** Used for "Go" actions, healthy selections, and successful states. It represents freshness and vitality.
- **Secondary (Vibrant Orange):** Derived from the "Bite" in the logo, used for highlights, cart notifications, and calls-to-action that require urgency (e.g., "Order Now").
- **Neutral (Cool Greys):** A clean spectrum of whites and light greys ensures the interface feels airy and allows food photography to stand out without competition.
- **Surface:** Pure white is used for elevated cards to create clear separation from the light-grey background.

## Typography
**Inter** is selected for its exceptional legibility and modern, neutral tone. The typographic hierarchy follows M3 standards to ensure clear communication of food names, prices, and nutritional data. 

- **Headlines:** Bold and tight to give a sense of structure.
- **Body:** Standardized at 16px for primary descriptions to ensure accessibility for students scanning menus on the move.
- **Labels:** Used for tags (e.g., "Vegan," "Gluten-Free") and secondary meta-data like "10 mins wait."

## Layout & Spacing
The layout uses a **Fluid Grid** system based on an 8px square rhythm.
- **Mobile:** 4-column grid with 16px side margins. Cards usually span the full width or 2 columns for smaller items.
- **Desktop/Tablet:** 12-column grid centered in a max-width container (1280px). 
- **Rhythm:** Generous vertical whitespace between menu categories to prevent the interface from feeling cluttered. Content is grouped in containers with 16px of internal padding to maintain a breathable feel.

## Elevation & Depth
In line with Material Design 3, this design system uses **Tonal Layers** supplemented by **Ambient Shadows**. 
- **Level 0 (Background):** Light Grey (#F8F9FA).
- **Level 1 (Cards):** White surface with a subtle 4% black shadow (blur 8px, Y 2px). This creates a "lifted" effect for interactive food items.
- **Level 2 (Buttons/Active States):** Increased shadow depth (8% opacity, blur 12px) to indicate interactivity.
- **Scrolled States:** App bars gain a subtle tonal tint of the primary color or a faint bottom border to indicate elevation over content.

## Shapes
The shape language is defined by **Soft Roundedness**. 
- **Standard Cards:** 16px (`rounded-lg`) corner radius to evoke a friendly, approachable feel.
- **Buttons & Chips:** 24px+ (`rounded-xl` or full pill) to make touch targets obvious and "squishy."
- **Images:** All food photography must have a minimum 12px radius to match the container logic.

## Components
- **Food Cards:** Feature a top-aligned image (aspect ratio 16:9), followed by title, short description, and a floating "+" button in the bottom right using the Secondary color.
- **Primary Buttons:** High-emphasis, pill-shaped, using the Primary Fresh Green. Text is white, Medium weight.
- **Status Chips:** Small, rounded-pill containers for dietary labels. Use low-saturation backgrounds (e.g., light green for Vegan, light orange for Spicy) with high-contrast text.
- **Search Bar:** A prominent, rounded input field with a subtle shadow and a leading search icon, pinned to the top of the menu for quick navigation.
- **Cart Fab:** A floating action button in the Secondary Orange, positioned in the bottom right, displaying the current item count in a small white badge.
- **Input Fields:** Outlined style with 12px corner radius. The outline thickens and changes to Primary color on focus.