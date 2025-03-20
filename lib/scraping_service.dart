import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<List<Map<String, dynamic>>> scrapeMaterie() async {
  final browser = await puppeteer.launch(
    headless: true,
  ); // headless: true per esecuzione in background
  final page = await browser.newPage();

  // Naviga alla pagina di login
  await page.goto(
    'https://servizi1.isidata.net/SSDidatticheco/Allievi/LoginAllieviRes.aspx',
  );

  await page.waitForSelector('#ctl00_cp1_Istituto_I', visible: true);

  // Seleziona l'istituto (es. "TSCO" per Trieste)
  await page.evaluate(r'''
    if (typeof ASPxClientComboBox !== "undefined") {
      var combo = ASPxClientComboBox.Cast("ctl00_cp1_Istituto");
      if (combo) {
        combo.SetValue("TSCO");
      }
    }
  ''');

  // Inserisci matricola e password
  await page.type('#ctl00_cp1_codice_I', '3532');
  await page.type('#ctl00_cp1_psv_I', 'Mtm03sf04-');

  // Clicca sul bottone di login e attendi la navigazione
  await Future.wait([
    page.waitForNavigation(),
    page.click('#ctl00_cp1_LoginButton'),
  ]);

  // Naviga alla pagina degli esami
  await page.goto(
    'https://servizi1.isidata.net/SSDidatticheco/Allievi/Esami/Esami_breveres.aspx',
  );

  // Attendi che la griglia sia caricata (almeno un elemento dei crediti è visibile)
  await page.waitForSelector("span[id*='cre']", visible: true);

  // Esegui l'estrazione dei dati iterando sulle righe della griglia
  final materie = await page.evaluate(r'''
    (() => {
      let results = [];
      let currentMateria = {};

      // Seleziona tutte le righe utili della griglia
      const rows = document.querySelectorAll("tr.NoCell, tr.SiCell");
      
      rows.forEach(row => {
        // Se esiste un elemento che contiene la materia, usiamo il suo valore
        const materiaNode = row.querySelector("span[id*='Label1']");
        if (materiaNode) {
          // Se abbiamo già una materia in corso, la aggiungiamo ai risultati
          if (Object.keys(currentMateria).length !== 0) {
            results.push(currentMateria);
            currentMateria = {};
          }
          currentMateria["materia"] = materiaNode.innerText.trim();
          
          // Cerca anno e voto nella stessa riga
          const annoNode = row.querySelector("span[id*='Label4']");
          if (annoNode) {
            currentMateria["anno"] = annoNode.innerText.trim();
          }
          const votoNode = row.querySelector("span[id*='mv1']");
          if (votoNode) {
            currentMateria["voto"] = votoNode.innerText.trim();
          }
          
          // Estrazione dei crediti tramite mapping dell'id
          let idMatch = materiaNode.id.match(/cell(\d+)_/);
          let rowNumber = idMatch ? idMatch[1] : null;
          if (rowNumber) {
            const creditSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_cre"]`);
            if (creditSpan) {
              currentMateria["crediti"] = creditSpan.innerText.trim();
            }

            // Estrazione delle ore totali
            const oreTotaliSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_ofp"]`);
            if (oreTotaliSpan) {
              currentMateria["ore_totali"] = oreTotaliSpan.innerText.trim();
            }

            // Estrazione delle ore fatte
            const oreFatteSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_of"]`);
            if (oreFatteSpan) {
              currentMateria["ore_fatte"] = oreFatteSpan.innerText.trim();
            }
          }

          // Professore (mapping dinamico)
            const profSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_tD"]`);
            if (profSpan) {
              currentMateria["professore"] = profSpan.innerText.trim();
            }
        } else {
          // Se la riga non contiene la materia, integra dati come anno e voto
          const annoNode = row.querySelector("span[id*='Label4']");
          if (annoNode && !currentMateria["anno"]) {
            currentMateria["anno"] = annoNode.innerText.trim();
          }
          const votoNode = row.querySelector("span[id*='mv1']");
          if (votoNode && !currentMateria["voto"]) {
            currentMateria["voto"] = votoNode.innerText.trim();
          }
        }
      });
      
      // Aggiungi l'ultimo oggetto se presente
      if (Object.keys(currentMateria).length !== 0) {
        results.push(currentMateria);
      }
      
      return results;
    })();
  ''');

  await browser.close();
  return List<Map<String, dynamic>>.from(materie);
}

void main() async {
  // Configura il middleware e il routing con Shelf
  var handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler((shelf.Request request) async {
        if (request.url.path == 'scrape') {
          try {
            final data = await scrapeMaterie();
            return shelf.Response.ok(
              jsonEncode(data),
              headers: {'Content-Type': 'application/json'},
            );
          } catch (e) {
            return shelf.Response.internalServerError(body: 'Errore: $e');
          }
        }
        return shelf.Response.notFound('Endpoint non trovato');
      });

  // Avvia il server sulla porta 8080, su tutte le interfacce IPv4
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server in ascolto su http://${server.address.host}:${server.port}');
}
