# Vende Móvil — estructura del proyecto

Reorganizado en carpetas de un solo nivel (nada anidado más allá de
`lib/<carpeta>/<archivo>.dart`), agrupando los archivos según lo que ya
sugería la Parte 0 del prompt:

```
lib/
├── main.dart
├── theme.dart                    # Parte 11 — paleta, tipografía, ThemeData
├── models/
│   └── models.dart               # Parte 1 — Category, Product, Seller, Sale...
├── data/
│   └── database.dart             # Parte 1 — DatabaseHelper (sqflite)
├── providers/
│   └── cart_provider.dart        # Carrito compartido (Partes 2, 6, 7)
├── screens/
│   ├── home_screen.dart          # Parte 2 + 3 — cámara/carrito + menú lateral
│   ├── catalog_screen.dart       # Parte 6 — catálogo en grid
│   ├── product_screens.dart      # Parte 4 + 5 — inventario + nuevo producto
│   ├── checkout_screen.dart      # Parte 7 — revisar orden / checkout
│   ├── sales_history_screen.dart # Parte 9 — historial de ventas
│   └── settings_screen.dart      # Parte 10 — ajustes
└── utils/
    ├── utils.dart                # formato de moneda, copiar fotos
    ├── permissions.dart          # Parte 12 — permisos en tiempo de ejecución
    └── printing.dart             # Parte 8 — generación/envío del ticket ESC/POS

android/app/src/main/AndroidManifest.xml   # Parte 12 — permisos de cámara/Bluetooth
pubspec.yaml
```

## Qué se corrigió en esta pasada

1. **Vendedor activo (hueco de las Partes 1/7/8)**: en Ajustes → Vendedores
   ahora se puede marcar cuál es el "vendedor activo" (incluye la opción
   "Ninguno"). Ese id se guarda en `AppSettings.activeSellerId`
   (columna nueva en `app_settings`, con migración `onUpgrade` de la base
   de datos para no romper instalaciones existentes) y `checkout_screen.dart`
   lo usa como `sellerId` de la venta en vez de `null`. `printing.dart` ya
   buscaba el nombre del vendedor por `sellerId` para el "Atendido por" del
   ticket, así que ese dato ahora sí llega.
2. **Reestructuración de carpetas**: un solo nivel de profundidad, sin
   sub-sub-carpetas, siguiendo los mismos nombres que ya proponía la Parte 0
   del prompt (`models/`, `data/`, `providers/`, `screens/`, `utils/`).

## Pendiente conocido (no bloqueante)

- La variante de la Parte 5 donde `NewProductScreen` se muestra con la
  cámara semi-visible de fondo (cuando se llega desde "código no
  encontrado") no está implementada: hoy se abre como pantalla opaca
  normal. Es un efecto visual, no afecta la funcionalidad.
- El `AndroidManifest.xml` fue generado desde cero (no subiste una carpeta
  `android/`), asumiendo el scaffold estándar de `flutter create`. Si ya
  tienes tu propio proyecto Android, copia solo el bloque de
  `<uses-permission>` / `<uses-feature>` dentro de tu manifest real en vez
  de reemplazarlo entero.
