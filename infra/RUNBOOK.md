# RUNBOOK — Publicar el Observatorio Económico en el VPS del SATQ

Guía para poner **`observatorio-web`** en línea en el VPS de Hostinger que ya hospeda
n8n, Pacia, Typebot y el Wizard REC — **sin romper nada de lo que ya funciona**.

El sitio es 100 % estático (2 páginas HTML + 2 imágenes, sin backend ni build step). Se
sirve con nginx dentro de un contenedor que se **cuelga del Traefik que ya existe** (el
del stack de n8n) para obtener HTTPS automático. No se instala ningún proxy nuevo, no se
publican puertos y no se toca el 80/443.

> **Datos del servidor:** IP `187.77.13.82` · Ubuntu 24.04 · Traefik `n8n-traefik-1`
> dueño de 80/443 · red Docker `n8n_default` · certresolver `mytlschallenge`.
>
> **Dominio destino:** `https://observatorio.srv1682335.hstgr.cloud`

---

## ⚠️ Léeme: en este VPS **no hay Portainer**

Verificado el **2026-08-18** en el *Administrador de Docker* de Hostinger: los proyectos
existentes son `docker`, `n8n`, `pacia`, `satq-wizard` y `typebot-satq`. **No existe
ningún contenedor de Portainer**, y `https://187.77.13.82:9443` no responde.

La documentación de `satq-wizard` (`satq-wizard/infra/RUNBOOK.md`) describe un flujo por
Portainer que **no corresponde a la realidad del servidor**. El método que realmente se
usa —y el que sigue esta guía— es **SSH + `docker compose`**, que es también lo que hace
el workflow `satq-wizard CI/CD` de n8n (`git pull` + rebuild por SSH).

**El panel de Hostinger (*Administrador de Docker*) sirve para ver y administrar**, pero
**no** para crear este stack: su editor visual pide una **imagen ya construida**, y
nuestro `docker-compose.yml` usa `build:` (construye desde el código del repo). Si
intentas desplegarlo desde ahí, falla.

---

## 0. DNS — nada que hacer ✅

El dominio base `srv1682335.hstgr.cloud` tiene un registro **wildcard**: *cualquier*
subdominio ya resuelve a `187.77.13.82`. Verificado el **2026-08-18**:

```bash
dig +short observatorio.srv1682335.hstgr.cloud   # → 187.77.13.82
```

No hay que agregar ningún registro A en el panel de Hostinger. Traefik podrá emitir el
certificado en cuanto el contenedor levante.

---

## 1. Credenciales — ninguna ✅

El repo `proyectos-gob/observatorio-web` es **público** desde el **2026-08-18**, así que
`git clone` y `git pull` funcionan **sin token**. No hay ningún secreto guardado en el
VPS para este proyecto y no hay nada que rotar.

> **Por qué se hizo público:** el sitio se sirve abiertamente a los ciudadanos y el repo
> solo contiene 2 HTML, 2 PNG y esta documentación — sin secretos ni PII. Se intentó
> primero con un fine-grained PAT, pero `git clone` devolvía **403**: la organización
> exige aprobación del owner para ese tipo de tokens. Hacerlo público eliminó el
> problema de raíz en vez de administrar un token que hay que renovar cada 90 días.
>
> **Si algún día vuelve a ser privado:** hay que crear un fine-grained PAT desde la
> **cuenta personal** (https://github.com/settings/personal-access-tokens/new — NO desde
> el *Developer settings* de la org, que solo tiene OAuth/GitHub Apps), con *Resource
> owner* = `proyectos-gob`, *Contents: Read-only*, y **aprobarlo** en Org → *Settings →
> Third-party Access → Personal access tokens → Pending requests*. Sin esa aprobación el
> clone falla con 403.

---

## 2. Desplegar (desde la Consola web de Hostinger)

En hPanel → VPS → **Administrador de Docker** → botón **Consola web** (arriba a la
derecha). Da terminal como `root` en el VPS sin configurar llaves SSH.

**Antes de empezar:** si creaste un proyecto vacío llamado `observatorio-web` desde el
editor visual del panel, **bórralo** — chocaría con el nombre del proyecto compose.

```bash
# 1) Confirma dónde vive el wizard, para seguir la misma convención
docker inspect satq-wizard \
  --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'

# 2) Clona el repo (público: sin credenciales)
mkdir -p /opt && cd /opt
git clone https://github.com/proyectos-gob/observatorio-web.git
cd /opt/observatorio-web

# 3) Construye y levanta
docker compose up -d --build
```

> **Convención de rutas:** el wizard vive en `/opt/satq-wizard` (verificado con
> `docker inspect satq-wizard --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'`),
> por eso este va en `/opt/observatorio-web`. Manténlo así.

---

## 3. Verificar

En el VPS:

```bash
docker compose -f /opt/observatorio-web/docker-compose.yml ps   # debe decir healthy
docker compose -f /opt/observatorio-web/docker-compose.yml logs --tail=20
```

Desde tu Mac:

```bash
# 1) Responde y el certificado es válido (sin -k, para que falle si el TLS está mal)
curl -I https://observatorio.srv1682335.hstgr.cloud

# 2) El mapa que se carga en el iframe
curl -s -o /dev/null -w "%{http_code}\n" https://observatorio.srv1682335.hstgr.cloud/mapa-qroo.html

# 3) HTTP debe redirigir a HTTPS (301/308)
curl -sI http://observatorio.srv1682335.hstgr.cloud | head -1
```

> **Si el certificado falla los primeros segundos:** Let's Encrypt tarda en emitirlo.
> Espera 1–2 min y reintenta. Si sigue fallando, revisa `docker logs n8n-traefik-1`.

---

## 4. Actualizar el sitio después

`git push` a `main` desde tu Mac, y en la Consola web del VPS:

```bash
cd /opt/observatorio-web && git pull && docker compose up -d --build
```

Los HTML se sirven con `Cache-Control: no-cache`, así que el cambio se ve de inmediato en
el navegador del visitante, sin pedirle que limpie caché. Downtime: unos segundos.

---

## Cómo está armado

| Archivo | Qué hace |
|---|---|
| `Dockerfile` | `nginx:1.27-alpine` + copia de los estáticos. Sin build ni npm. |
| `nginx.conf` | Gzip (81 KB → 26 KB), cache de assets 7 días, HTML sin cache, `/healthz`. |
| `docker-compose.yml` | Red `n8n_default` + labels de Traefik (router `observatorio`, puerto 80). |
| `.dockerignore` | Evita que `.git`, README e infra entren a la imagen. |

**Detalles que ya mordieron una vez** (para que no vuelvan a morder):

- El healthcheck usa **`127.0.0.1`, no `localhost`**: dentro del contenedor `localhost`
  resuelve primero a `::1` (IPv6) y nginx solo escucha en IPv4 → daba *unhealthy*.
- `.dockerignore` **no debe excluir `nginx.conf`**: el Dockerfile lo copia.
- El editor visual de Hostinger **no sirve** para este stack: pide `image:`, no `build:`.

**Dependencias externas del sitio:** Google Fonts y Leaflet (vía `unpkg.com`) se cargan
desde CDN en el navegador del visitante. Si alguna vez debe funcionar en una red de
gobierno con salida restringida, hay que bajar esos archivos al repo.

---

## Verificado localmente antes del primer deploy (2026-08-18)

Se construyó y corrió la imagen en la Mac antes de tocar el VPS:

| Prueba | Resultado |
|---|---|
| `docker build` | OK — imagen de 76.6 MB |
| `GET /` | 200 · `text/html` · 81 071 bytes |
| `GET /mapa-qroo.html` | 200 · 8 675 bytes |
| `GET /assets/logo-qroo.png` | 200 · `Cache-Control: public, max-age=604800` |
| Gzip en `/` | 81 071 → **25 952 bytes** |
| `GET /no-existe` | **404** (código correcto, sirviendo la página del sitio) |
| `GET /healthz` | 200 |
| Healthcheck de Docker | `healthy` |
| Contenido de la imagen | solo HTML + assets; sin `.git`, README ni compose |
| `docker compose config` | sintaxis válida |

---

## Verificado EN PRODUCCIÓN (2026-08-18, tras el primer deploy)

Comprobado desde fuera del VPS contra `https://observatorio.srv1682335.hstgr.cloud`:

| Prueba | Resultado |
|---|---|
| `GET /` | 200 · `text/html` · 81 071 bytes · `nginx/1.27.5` |
| `GET /mapa-qroo.html` | 200 · 8 675 bytes |
| `GET /assets/logo-qroo.png` | 200 · `image/png` · 135 135 bytes |
| `GET /healthz` | 200 |
| HTTP → HTTPS | **308** Permanent Redirect |
| Certificado TLS | válido (Let's Encrypt vía Traefik; `curl` sin `-k` pasa) |
| `Cache-Control` del HTML | `no-cache, must-revalidate` |
| HSTS | `max-age=315360000; includeSubDomains; preload` |
| `X-Content-Type-Options` | `nosniff` |
| `X-XSS-Protection` | `1; mode=block` |
