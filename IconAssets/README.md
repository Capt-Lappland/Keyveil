# Keyveil Icon Source

The icon follows Apple's layered Icon Composer workflow:

1. Run `swift scripts/render-icon-layer.swift /tmp/keyveil-command-layer.png` to rasterize the custom geometric `command-symbol.svg` as a transparent 1024×1024 foreground layer using Apple's Core Graphics stack.
2. Import the resulting PNG into Icon Composer.
3. Keep the source canvas unmasked; Icon Composer applies the platform enclosure.
4. Set the canvas background to white in Icon Composer instead of baking a rounded rectangle into the artwork.
5. Keep the foreground in one group using Combined Liquid Glass with specular, translucency, and a neutral shadow enabled.
6. Preview the macOS Default, Dark, and Mono appearances at small sizes before saving `Keyveil.icon`.

The source layer is an original vector construction and intentionally contains no font dependency, blur, bevel, highlight, shadow, or glass simulation. Icon Composer and the operating system supply those effects dynamically.
