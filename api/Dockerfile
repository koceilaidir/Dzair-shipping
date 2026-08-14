# API Dzair Shipping — image de production
FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY scripts ./scripts
COPY db ./db

# L'API ne tourne jamais en root dans le conteneur.
USER node

EXPOSE 3000
CMD ["node", "src/server.js"]
