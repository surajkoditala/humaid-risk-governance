# Local-only container for the webapp (5-Presentation), so the whole solution can run as Docker
# containers on one machine without a separate `npm run dev`. This is NOT the team's target
# production deploy shape (see ops/README.md - that's a static build served by whichever static
# hosting the pipeline targets); this is a dev convenience: `npm run build` then `vite preview`.
#
# Build context is this folder (webapp/), unlike the two .NET Dockerfiles - the webapp has no
# sibling ProjectReference, so it doesn't need the repo root:
#   docker build -f webapp/Dockerfile -t humaid-webapp webapp/
#
# VITE_* values are baked in at BUILD time (Vite inlines import.meta.env at build, not at
# container start), so they're build args, not just runtime env - see ops/docker-compose.app.yml.

FROM node:20-alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install

COPY . .

ARG VITE_API_BASE_URL=http://localhost:5210
ARG VITE_AUTH0_DOMAIN=
ARG VITE_AUTH0_CLIENT_ID=
ARG VITE_AUTH0_AUDIENCE=
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL \
    VITE_AUTH0_DOMAIN=$VITE_AUTH0_DOMAIN \
    VITE_AUTH0_CLIENT_ID=$VITE_AUTH0_CLIENT_ID \
    VITE_AUTH0_AUDIENCE=$VITE_AUTH0_AUDIENCE

RUN npm run build

EXPOSE 4173
CMD ["npx", "vite", "preview", "--host", "0.0.0.0", "--port", "4173"]
