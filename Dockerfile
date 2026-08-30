FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY . .
ENV NODE_ENV=production
ENV START_SERVER=true
EXPOSE 8787
CMD ["node", "server/index.js"]
