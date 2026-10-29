FROM node:20-alpine AS base
WORKDIR /app

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY tsconfig.json ./
COPY prisma ./prisma
RUN npx prisma generate
COPY src ./src
RUN npm run build

EXPOSE 8080
CMD ["sh", "-c", "npx prisma db push && npm run start"]
