# Usa l'immagine ufficiale di Dart per la fase di build
FROM dart:stable AS build

# Imposta la cartella di lavoro
WORKDIR /app

# Copia i file dei package e installa le dipendenze
COPY pubspec.* /app/
RUN dart pub get

# Copia il resto dei file
COPY . /app/

# Compila lo script Dart per una esecuzione più veloce (facoltativo)
RUN dart compile exe bin/scraping_service.dart -o bin/scraping_service

# Usa un'immagine più snella per il runtime
FROM scratch
COPY --from=build /runtime/ /runtime/
COPY --from=build /app/bin/scraping_service /app/bin/scraping_service

# Espone la porta 8080
EXPOSE 8080

# Comando da eseguire all'avvio del container
CMD ["/app/bin/scraping_service"]
