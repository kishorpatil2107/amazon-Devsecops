# # ---------- Build Stage ----------
# FROM node:alpine AS build

# # Set working directory
# WORKDIR /app

# # Copy dependency files
# COPY package*.json ./

# # Install dependencies
# RUN npm install

# # Copy rest of the code
# COPY . .

# # Build optimized production build
# RUN npm run build


# # ---------- Production Stage ----------
# FROM nginx:alpine

# # Copy build output to nginx html directory
# COPY --from=build /app/build /usr/share/nginx/html

# # Expose port 80
# EXPOSE 80

# # Start nginx
# CMD ["nginx", "-g", "daemon off;"]
# # ---------- End of Dockerfile ----------
# ---------- Build Stage ----------
FROM node:20-alpine AS build

# Set working directory
WORKDIR /app

# Copy dependency files first (better caching)
COPY package*.json ./

# Install dependencies (use ci for reproducibility)
RUN npm ci --only=production

# Copy the rest of the code
COPY . .

# Build optimized production build
RUN npm run build

# ---------- Production Stage ----------
FROM nginx:alpine

# Remove default nginx page
RUN rm -rf /usr/share/nginx/html/*

# Copy build output from build stage
COPY --from=build /app/build /usr/share/nginx/html

# Copy custom nginx config (optional, if you have one)
# COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
# ---------- End of Dockerfile ----------

