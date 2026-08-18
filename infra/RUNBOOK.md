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

## 1. Token de GitHub (el repo es privado)

El VPS necesita credenciales para clonar `proyectos-gob/observatorio-web`. Usa un
**fine-grained PAT de solo lectura**.

> ⚠️ Los fine-grained PAT se crean en tu **cuenta personal**, NO en la organización. El
> *Developer settings* de la org solo tiene OAuth Apps / GitHub Apps / Publisher
> Verification. Ruta correcta:
> **https://github.com/settings/personal-access-tokens/new**

1. **Resource owner:** `proyectos-gob` (este paso lo convierte en token de la org).
2. **Repository access:** *Only select repositories* → **`observatorio-web`**.
3. **Permissions → Repository permissions → Contents: Read-only**. Con eso basta.
4. **Expiration:** ponle fecha (p. ej. 90 días) y agenda la rotación.
5. Nómbralo `portainer-vps-satq · observatorio-web · RO` o similar: quién lo usa, a qué
   accede, con qué permiso.

> Si la org exige aprobación, el token queda en **Pending** y no funciona hasta
> aprobarlo en Org → *Settings → Personal access tokens → Pending requests*. Síntoma
> típico: `git clone` falla con un error de autenticación poco claro.

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

# 2) Clona el repo (sustituye TU_USUARIO y TU_PAT)
mkdir -p /opt && cd /opt
git clone https://TU_USUARIO:TU_PAT@github.com/proyectos-gob/observatorio-web.git
cd /opt/observatorio-web

# 3) Restringe permisos: el PAT queda guardado en .git/config
chmod 700 /opt/observatorio-web

# 4) Construye y levanta
docker compose up -d --build
```

> **Sobre el PAT en `.git/config`:** queda en texto plano en el servidor. Es un token
> *read-only* limitado a un solo repo cuyo contenido es un sitio público, así que el
> riesgo es bajo — pero **hay que rotarlo** cuando expire o el `git pull` dejará de
> funcionar. Alternativa que elimina el secreto por completo: hacer **público** el repo
> (el sitio va a ser público de todos modos) y clonar sin credenciales.

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
