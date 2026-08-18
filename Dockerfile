# ============================================================================
#  Observatorio Económico Q. Roo — imagen estática.
#
#  El sitio no tiene build ni dependencias: son archivos HTML que nginx sirve
#  tal cual. La imagen solo copia los estáticos sobre nginx:alpine.
#
#  No expone puertos al host: Traefik (el del stack de n8n) le habla por la
#  red interna de Docker al puerto 80. Ver docker-compose.yml.
# ============================================================================
FROM nginx:1.27-alpine

# Configuración del server block (gzip, cache, 404 amable, /healthz).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Los estáticos del sitio. Lo que NO debe entrar está en .dockerignore.
COPY index.html mapa-qroo.html /usr/share/nginx/html/
COPY assets/ /usr/share/nginx/html/assets/

# nginx:alpine ya trae CMD y EXPOSE 80; no hay nada que agregar.
