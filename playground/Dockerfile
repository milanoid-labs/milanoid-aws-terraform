# nginx is multi-arch: on the arm64 runner the plain FROM resolves to arm64
# natively - no QEMU/binfmt. This is the point of the playground.
FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
