# RUNBOOK — Publicar el Observatorio Económico en el VPS del SATQ

Guía para poner **`observatorio-web`** en línea en el VPS de Hostinger que ya hospeda
n8n, Pacia y el Wizard REC — **sin romper nada de lo que ya funciona**.

El sitio es 100 % estático (2 páginas HTML + 2 imágenes, sin backend ni build). Se sirve
con nginx dentro de un contenedor que se **cuelga del Traefik que ya existe** (el del
stack de n8n) para obtener HTTPS automático. No se instala ningún proxy nuevo, no se
publican puertos y no se toca el 80/443.

> **Datos del servidor:** IP `187.77.13.82` · Ubuntu 24.04 · Traefik `n8n-traefik-1`
> dueño de 80/443 · red Docker `n8n_default` · certresolver `mytlschallenge`.
>
> **Dominio destino:** `https://observatorio.srv1682335.hstgr.cloud`

---

## 0. DNS — nada que hacer ✅

El dominio base `srv1682335.hstgr.cloud` tiene un registro **wildcard**: *cualquier*
subdominio ya resuelve a `187.77.13.82`. Verificado el **2026-08-18**:

```bash
dig +short observatorio.srv1682335.hstgr.cloud   # → 187.77.13.82
```

No hay que agregar ningún registro A en el panel de Hostinger. Traefik podrá emitir el
certificado en cuanto el stack levante.

---

## 1. Token de GitHub (el repo es privado)

Portainer necesita credenciales para clonar `proyectos-gob/observatorio-web`. Usa un
**fine-grained PAT de solo lectura**:

1. GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained
   tokens → Generate new token**.
2. **Resource owner:** `proyectos-gob`.
3. **Repository access:** *Only select repositories* → **`proyectos-gob/observatorio-web`**.
4. **Permissions → Repository permissions → Contents: Read-only**. Con eso basta.
5. **Expiration:** ponle fecha (p. ej. 90 días) y agenda la rotación.
6. Genera y **copia el token** (`github_pat_...`). Se usa una sola vez; Portainer lo guarda.

> Si ya existe un PAT para el stack de `satq-wizard`, **no lo reutilices**: ese está
> limitado a ese repo. Genera uno nuevo apuntando a este.

---

## 2. Crear el stack en Portainer

Portainer ya está instalado en el VPS: **`https://187.77.13.82:9443`** (el navegador
avisará del certificado propio → "Avanzado → continuar").

**Stacks → + Add stack:**

| Campo | Valor |
|---|---|
| **Name** | `observatorio-web` |
| **Build method** | *Repository* |
| **Repository URL** | `https://github.com/proyectos-gob/observatorio-web` |
| **Repository reference** | `refs/heads/main` |
| **Compose path** | `docker-compose.yml` |
| **Authentication** | ON → usuario de GitHub + el PAT del paso 1 como contraseña |
| **Environment variables** | **ninguna** — este stack no tiene secretos |

Presiona **Deploy the stack**. La primera vez tarda ~1 min (descarga `nginx:1.27-alpine`
y construye la imagen).

---

## 3. Verificar

Desde tu Mac:

```bash
# 1) Responde y el certificado es válido (sin -k, para que falle si el TLS está mal)
curl -I https://observatorio.srv1682335.hstgr.cloud

# 2) El mapa que se carga en el iframe
curl -s -o /dev/null -w "%{http_code}\n" https://observatorio.srv1682335.hstgr.cloud/mapa-qroo.html

# 3) HTTP debe redirigir a HTTPS (301/308)
curl -sI http://observatorio.srv1682335.hstgr.cloud | head -1
```

En Portainer, el contenedor `observatorio-web` debe aparecer como **healthy**
(el healthcheck pega a `/healthz`).

> **Si el certificado falla los primeros segundos:** Let's Encrypt tarda en emitirlo.
> Espera 1–2 min y reintenta. Si sigue fallando, revisa los logs de `n8n-traefik-1`.

---

## 4. Actualizar el sitio después

`git push` a `main` → en Portainer: **Stacks → `observatorio-web` → Pull and redeploy**.

Los HTML se sirven con `Cache-Control: no-cache`, así que el cambio se ve de inmediato
en el navegador del ciudadano, sin pedirle que limpie caché. Downtime: unos segundos.

> **Auto-deploy (opcional):** Portainer tiene *GitOps updates* (polling cada X minutos o
> webhook). No está activado a propósito — para un sitio institucional conviene que la
> publicación sea un acto deliberado.

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
