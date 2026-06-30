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
  primary: '#0e631b'
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
  tertiary-container: '#2f6fb9'
  on-tertiary-container: '#ecf1ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#a3f69c'
  primary-fixed-dim: '#88d982'
  on-primary-fixed: '#002203'
  on-primary-fixed-variant: '#005312'
  secondary-fixed: '#ffdcc2'
  secondary-fixed-dim: '#ffb77a'
  on-secondary-fixed: '#2e1500'
  on-secondary-fixed-variant: '#6d3a00'
  tertiary-fixed: '#d4e3ff'
  tertiary-fixed-dim: '#a5c8ff'
  on-tertiary-fixed: '#001c3a'
  on-tertiary-fixed-variant: '#004785'
  background: '#f8f9fa'
  on-background: '#191c1d'
  surface-variant: '#e1e3e4'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 57px
    fontWeight: '700'
    lineHeight: 64px
    letterSpacing: -0.25px
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  headline-sm:
    fontFamily: Plus Jakarta Sans
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
    fontWeight: '600'
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
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  xs: 4px
  base: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  container-margin: 16px
  gutter: 16px
---

## Brand & Style

Campus Bite is a vibrant, student-centric food discovery and ordering platform. The brand personality is energetic, efficient, and approachable, designed to fit seamlessly into a fast-paced university lifestyle. 

The visual style follows a **Modern Corporate** aesthetic with a **Tactile** twist. It utilizes a fresh "Forest and Amber" color palette to evoke feelings of freshness (green) and appetite/warmth (orange). The UI balances clean, systematic Material Design 3 principles with playful micro-interactions—such as the "bouncy" food cards and scale-transformed buttons—to feel responsive and alive. The use of backdrop blurs and subtle outlines ensures the interface feels lightweight and contemporary.

## Colors
The color system is rooted in high-fidelity organic tones. 

- **Primary Forest Green (#0d631b):** Used for branding, price points, and primary actions. It signals growth and freshness.
- **Secondary Amber (#8f4e00 / #ff8f06):** Used for highlighting active states, categories, and urgent "Flash Deals." It provides a warm, appetizing contrast to the green.
- **Neutral Backgrounds (#f8f9fa):** A cool, off-white surface that reduces eye strain and allows colorful food photography to take center stage.
- **Semantic Accents:** Surfaces use a tiered container system (Lowest to Highest) to create subtle hierarchy without heavy shadows.

## Typography
Typography is optimized for legibility and personality. 

We utilize **Plus Jakarta Sans** for Headlines to provide a friendly, rounded, and welcoming feel. **Inter** is used for body text and labels to maintain high readability and a systematic, clean look for technical details like prices and descriptions. 

Scale is used aggressively to differentiate roles: large, bold headlines for page exploration and smaller, tightly-spaced labels for metadata within cards.

## Layout & Spacing
The system uses a **Fluid Grid** approach for mobile, transitioning to a **Fixed Max-Width (4xl/896px)** container for larger screens to preserve focus.

- **Margins:** A standard 16px (container-margin) is applied to the left and right of the viewport.
- **Grid:** A 2-column grid is used for product listings on mobile to maximize content density, increasing to 3 or 4 columns on desktop.
- **Rhythm:** An 8px base unit drives all spacing. Component internals typically use 8px (base) or 12px (sm) padding, while sections are separated by 24px (lg) or 32px (xl) to create clear visual breathing room.

## Elevation & Depth
Elevation is primarily expressed through **Tonal Layers** and **Subtle Outlines** rather than heavy shadows.

1.  **Background:** The base layer is `#f8f9fa`.
2.  **Cards & Containers:** Raised elements use `#ffffff` (Surface Lowest) with a 1px border of `surface-container-highest` or `outline-variant`.
3.  **App Bars:** The Top App Bar uses a `backdrop-blur-md` with 80% opacity to maintain context of the content scrolling beneath it.
4.  **Shadows:** When used (e.g., FABs or Banners), shadows are "Small" (shadow-sm) or "Large" (shadow-lg) with low opacity (10-15%) to avoid a muddy look.

## Shapes
The shape language is "Rounded," reflecting the friendly and approachable brand personality.

- **Cards:** Use `rounded-xl` (1.5rem / 24px) for a soft, friendly appearance.
- **Buttons:** Primary action buttons (Add to cart) use `rounded-lg` (1rem / 16px).
- **Chips & Filters:** Use `rounded-full` (Pill-shaped) to distinguish them as interactive, selectable elements.
- **Navigation:** The bottom bar features `rounded-t-xl` to "hug" the bottom of the screen.

## Components

### Buttons
- **Primary:** High-contrast `primary` background with `on-primary` text. Uses an active-state scale down (90%) for tactile feedback.
- **Icon Buttons:** Circular, using `surface-container` background with high-contrast icons.

### Chips (Filters)
- **Inactive:** `surface-container-lowest` background with an `outline-variant` border and `on-surface-variant` text.
- **Active:** `secondary-container` background with `on-secondary-container` text and matching border.

### Food Cards
- A vertical stack comprising a fixed-height image (h-32) and a padded content area. 
- Must include a favorite toggle (top-right) and a clear price-to-action alignment at the bottom.

### Banners
- High-impact, full-width containers using `primary` or `secondary` backgrounds. 
- Use semi-transparent decorative icons and bold label tags (e.g., "Flash Deal") to draw immediate attention.

### Navigation
- **Bottom Bar:** Fixed, using `surface-container/95` with backdrop blur. Icons use Material Symbols (Fill: 0 for inactive, Fill: 1 for active).
- **FAB (Floating Action Button):** High-elevation `secondary-container` with a badge counter for the cart.