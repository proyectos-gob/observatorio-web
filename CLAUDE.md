# CLAUDE.md — Observatorio Económico · Quintana Roo

Guía para agentes que trabajen en este repo. Escribe en **español**, con **fechas absolutas**
y **sin secretos ni PII real**.

## Qué es esto

Sitio web del **Observatorio Económico de Quintana Roo**: un tablero público de indicadores
económicos del estado. Es un **prototipo funcional ya publicado**, no un experimento local.

**100 % estático.** No hay backend, no hay build step, no hay `package.json`, no hay
dependencias de npm. Son archivos HTML que un nginx sirve tal cual.

```
observatorio-web/
├── index.html          ← la aplicación completa (una sola base responsiva, ~81 KB)
├── mapa-qroo.html      ← mapa interactivo (Leaflet); index.html lo carga en un iframe
├── assets/
│   ├── logo-qroo.png       (logo institucional horizontal)
│   └── isotipo-qroo.png    (isotipo Q, favicon y avatar del asistente)
├── Dockerfile          ← nginx:1.27-alpine + copia de los estáticos
├── nginx.conf          ← gzip, cache, /healthz, manejo de 404
├── docker-compose.yml  ← red n8n_default + labels de Traefik
├── .dockerignore
├── README.md
└── infra/RUNBOOK.md    ← 📘 fuente de verdad del despliegue
```

## 🌐 Está EN PRODUCCIÓN

**https://observatorio.srv1682335.hstgr.cloud** — desplegado y verificado el **2026-08-18**.

Cualquier cambio que hagas aquí puede terminar frente a ciudadanos. Trátalo como
producción: verifica antes de afirmar que algo funciona.

## 🚧 Este proyecto es INDEPENDIENTE de SATQ

Aunque la carpeta viva dentro de `~/Dev/satq/`, **este es un proyecto aparte** (decisión del
2026-08-18). No pertenece a las entregas del chatbot/wizard del SATQ, no comparte código con
ellos y no debe contarse en su avance.

**Lo único que comparten es el servidor.** Por eso aplican las reglas de infraestructura de
abajo: en ese VPS conviven servicios de gobierno que **no debes tocar**.

## 🏛️ Reglas de infraestructura (críticas)

Todo el runtime vive en el **VPS del cliente** (Hostinger, `187.77.13.82`, Ubuntu 24.04),
donde conviven en Docker: **n8n** (orquestador + su **Traefik**, dueño de los puertos 80/443),
**Pacia**, **Dify**, **Typebot** y **`satq-wizard`**.

- ⛔ **No toques los otros stacks** (`n8n`, `pacia`, `docker`, `typebot-satq`, `satq-wizard`):
  no los reinicies, no los edites, no los detengas. Son servicios de gobierno en operación.
- ⛔ **No publiques puertos nuevos** ni instales otro proxy: este sitio se cuelga del
  **Traefik de n8n** (red Docker `n8n_default`, certresolver `mytlschallenge`).
- ⛔ **Nada de infraestructura personal del desarrollador** (Dokploy propio, servidores
  propios). Todo vive en el VPS del cliente.
- 🚨 **NO hay Portainer en este VPS** (verificado 2026-08-18; el puerto 9443 no responde).
  Si algún documento menciona desplegar por Portainer, está equivocado.
- 🌐 **El DNS `*.srv1682335.hstgr.cloud` es wildcard:** cualquier subdominio ya resuelve a
  `187.77.13.82`. Para publicar algo nuevo **no se piden registros A** — basta el `Host(...)`
  en los labels de Traefik.

## Desplegar y actualizar

**Un `git push` NO actualiza el sitio.** Son dos pasos.

En el VPS (terminal sin configurar llaves SSH: hPanel → VPS → *Administrador de Docker* →
botón **Consola web**, entra como `root`):

```bash
cd /opt/observatorio-web && git pull && docker compose up -d --build
```

⚠️ **El `--build` no es opcional.** Los HTML están *dentro* de la imagen (el Dockerfile los
copia), así que sin reconstruir, el contenedor sigue sirviendo los archivos viejos aunque el
`git pull` haya bajado los nuevos. Es el error clásico de este patrón.

Al visitante le llega de inmediato: los HTML se sirven con `Cache-Control: no-cache`. El corte
de servicio son unos segundos. Convención de rutas en el VPS: `/opt/<proyecto>`.

📘 **Detalle completo (primer deploy, verificación, problemas comunes):** `infra/RUNBOOK.md`.

## Trabajar en local

No hay servidor de desarrollo ni comandos de build. Para ver cambios basta abrir `index.html`
en el navegador. Para probar **exactamente lo que verá producción** (nginx, gzip, cache, 404):

```bash
docker build -t observatorio-web:test .
docker run -d --name obs-test -p 8099:80 observatorio-web:test
# abre http://localhost:8099   ·   al terminar: docker rm -f obs-test
```

Verificación rápida contra producción:

```bash
curl -I https://observatorio.srv1682335.hstgr.cloud          # 200 + cert válido (sin -k)
curl -s -o /dev/null -w "%{http_code}\n" https://observatorio.srv1682335.hstgr.cloud/mapa-qroo.html
```

## Convenciones y trampas conocidas

- **No agregues dependencias de npm ni un build step.** El valor de este repo es que
  cualquiera lo entiende y lo despliega sin cadena de herramientas. Es deliberado.
- **El healthcheck usa `127.0.0.1`, NO `localhost`:** dentro del contenedor `localhost`
  resuelve primero a `::1` (IPv6) y nginx solo escucha en IPv4 → el contenedor se marcaba
  *unhealthy* solo.
- **`.dockerignore` no debe excluir `nginx.conf`:** el Dockerfile lo copia; si lo excluyes,
  el build falla con un error confuso de checksum.
- **El editor visual del panel de Hostinger no sirve** para este stack: pide una `image:` ya
  construida y nuestro compose usa `build:`. Ese panel es para **ver y administrar**, no para
  crear.
- **404:** una ruta inexistente devuelve **404 de verdad** (no es una SPA), pero sirviendo la
  página del sitio en vez de la pantalla fea de nginx. No lo conviertas en `200`.
- **Dependencias externas por CDN:** Google Fonts y Leaflet (`unpkg.com`) se cargan desde el
  navegador del visitante. Funcionan bien, pero si algún día el sitio debe operar en una red
  de gobierno con salida restringida, hay que bajar esos archivos al repo.

## Repo y secretos

- **`proyectos-gob/observatorio-web`, público** desde el 2026-08-18 (el sitio es público de
  todos modos; el repo solo tiene HTML, imágenes y documentación).
- Como es público: **jamás** metas credenciales, tokens, endpoints internos ni PII. Este stack
  no tiene ni una variable de entorno, y así conviene que siga.
- Rama de trabajo: `main`.
