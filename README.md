# Observatorio Económico · Quintana Roo

Prototipo funcional listo para publicar. **Sin build step, sin dependencias de npm.** Se sirve como archivos estáticos.

## Contenido

```
observatorio-web/
├── index.html        ← la aplicación completa (una sola base responsiva)
├── mapa-qroo.html    ← mapa interactivo (se carga en un iframe desde index.html)
├── assets/
│   ├── logo-qroo.png     (logo institucional horizontal)
│   └── isotipo-qroo.png  (isotipo Q, favicon y avatar del asistente)
└── README.md
```

## Cómo publicar

Copiar la carpeta a cualquier servidor de archivos estáticos (Nginx, Apache, S3 + CloudFront, Netlify, Vercel, Cloudflare Pages, IIS). No requiere Node, PHP ni base de datos.

```bash
# prueba local
python3 -m http.server 8080
# → http://localhost:8080
```

**Importante:** debe servirse por HTTP, no abriendo el archivo con `file://` — el iframe del mapa y la carga de tiles lo requieren.

## Una sola base para web y móvil

No hay dos versiones: `index.html` es responsivo con un punto de quiebre en **900 px**.

| | Escritorio (≥ 901 px) | Móvil / tablet (≤ 900 px) |
|---|---|---|
| Navegación | Menú lateral colapsable con frosted glass | Barra inferior flotante con frosted glass (`env(safe-area-inset-bottom)` para el notch) |
| Rejillas | 2–4 columnas (`auto-fit / minmax`) | 1–2 columnas |
| Tablas | Rejilla de 4–5 columnas | Tarjetas apiladas con etiqueta por dato (`data-k` + `::before`) |
| Gráficas | Hover con crosshair y tooltip | Arrastre del dedo (Pointer Events) |
| Mapa | 452 px de alto, junto al ranking | 300 px de alto, arriba del ranking |

## Interacciones implementadas

- **Lectura ejecutiva**: una frase de interpretación arriba del panorama, redactada por periodo, con las cifras clave resaltadas y salto directo al asistente. Es lo primero que lee un tomador de decisiones. Los textos viven en el campo `brief` de cada periodo.
- **Filtro de periodo** (2020–2024) en el encabezado: recalcula PIB, crecimiento, aportación nacional, ocupados, desocupación, informalidad, PEA, composición del PIB, actividades y el corte del DENUE de los municipios. Se oculta en Fuentes y Preguntar, donde no aplica. En el mismo panel se cambia la serie del PIB entre **Anual** e **ITAEE trimestral**.
- **Gráfica del PIB**: crosshair con año, monto y variación contra el año anterior. Funciona con mouse y con dedo.
- **Tabla de la serie**: al tocar un año se fija el marcador en la gráfica.
- **Mapa** (`mapa-qroo.html`): Leaflet + tiles de OpenStreetMap con las coordenadas reales de los 11 municipios; burbujas proporcionales, toggle unidades económicas ⇄ empleo. Comunicación bidireccional con `index.html` vía `postMessage`:
  - mapa → app: `{ type: 'oq-municipio', municipio, data }`
  - app → mapa: `{ type: 'oq-select', municipio }` y `{ type: 'oq-reset' }`
- **Asistente** (Preguntar): respuestas por coincidencia de palabras clave, con tarjetas de datos, chip de fuente, salto a la sección correspondiente y preguntas de seguimiento.
- **Descargar datos**: genera un CSV de la serie del PIB en el navegador.

## Dónde conectar los datos reales

Todos los datos viven en el objeto **`DATA`** al inicio del `<script>` de `index.html`, y en **`MUN`** en `mapa-qroo.html`. Sustituir esos objetos por respuestas de la API (o un `fetch` que los pueble antes de llamar a las funciones de render) es el único cambio necesario; el render no se toca.

Llaves de `DATA`: `secciones`, `pib`, `itaee`, `variacion`, `composicion`, `subsectores`, `ficha`, `serie`, `empleo`, `ocupados`, `fuentes`, `municipios`, `periodos`, `sugerencias`, `respuestas`.

> Los valores actuales provienen de INEGI (SCNM, ITAEE, ENOE, DENUE) y de estimaciones propias etiquetadas como tales. Las cifras por periodo del filtro y las notas de contexto municipal son de demostración: validar contra la fuente oficial antes de publicar como dato de gobierno.

## Notas técnicas

- Tipografía **Schibsted Grotesk** desde Google Fonts. Para operar sin internet, descargar los `woff2` y declarar `@font-face` local.
- Los tiles de OpenStreetMap requieren salida a internet. Si el servidor está aislado, apuntar `L.tileLayer` a un servidor de tiles propio (la atribución de OSM es requisito de su licencia y no debe quitarse mientras se usen sus tiles).
- Accesibilidad: contraste AA verificado en todo el texto (auditado con luminancia relativa WCAG contra el fondo resuelto), `:focus-visible`, `aria-current` en navegación, `aria-pressed` en filtros, `role="img"` con `aria-label` en las gráficas y `prefers-reduced-motion` respetado.
- Sin cookies, sin analítica, sin almacenamiento local.
- Probado en Chrome, Safari (incluido iOS) y Firefox recientes. `backdrop-filter` degrada a fondo sólido translúcido donde no exista.
