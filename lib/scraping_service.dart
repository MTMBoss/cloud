import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<List<Map<String, dynamic>>> scrapeMaterie() async {
  final browser = await puppeteer.launch(headless: true);
  final page = await browser.newPage();

  // Naviga alla pagina di login
  await page.goto(
    'https://servizi1.isidata.net/SSDidatticheco/Allievi/LoginAllieviRes.aspx',
  );

  await page.waitForSelector('#ctl00_cp1_Istituto_I', visible: true);

  // Seleziona l'istituto
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

  // Esegui il login
  await Future.wait([
    page.waitForNavigation(),
    page.click('#ctl00_cp1_LoginButton'),
  ]);

  // Naviga alla pagina degli esami
  await page.goto(
    'https://servizi1.isidata.net/SSDidatticheco/Allievi/Esami/Esami_breveres.aspx',
  );

  await page.waitForSelector("span[id*='cre']", visible: true);

  // Esegui l'estrazione dei dati
  final materie = await page.evaluate(r'''
    (() => {
      let results = [];
      let currentMateria = {};

      const rows = document.querySelectorAll("tr.NoCell, tr.SiCell");
      
      rows.forEach(row => {
        const materiaNode = row.querySelector("span[id*='Label1']");
        if (materiaNode) {
          if (Object.keys(currentMateria).length !== 0) {
            results.push(currentMateria);
            currentMateria = {};
          }
          currentMateria["materia"] = materiaNode.innerText.trim();
          
          // Estrai dinamicamente l'id della riga
          let idMatch = materiaNode.id.match(/cell(\d+)_/);
          let rowNumber = idMatch ? idMatch[1] : null;
          
          if (rowNumber) {
            // Crediti
            const creditSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_cre"]`);
            if (creditSpan) {
              currentMateria["crediti"] = creditSpan.innerText.trim();
            }

            // Ore totali
            const oreTotaliSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_ofp"]`);
            if (oreTotaliSpan) {
              currentMateria["ore_totali"] = oreTotaliSpan.innerText.trim();
            }

            // Ore fatte
            const oreFatteSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_of"]`);
            if (oreFatteSpan) {
              currentMateria["ore_fatte"] = oreFatteSpan.innerText.trim();
            }

            // Professore (mapping dinamico)
            const profSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_tD"]`);
            if (profSpan) {
              currentMateria["professore"] = profSpan.innerText.trim();
            }

            // Voto (se disponibile)
            const votoSpan = document.querySelector(`span[id*="cell${rowNumber}_"][id*="_mv1"]`);
            if (votoSpan) {
              currentMateria["voto"] = votoSpan.innerText.trim();
            }
          }
          
          // Anno
          const annoNode = row.querySelector("span[id*='Label4']");
          if (annoNode) {
            currentMateria["anno"] = annoNode.innerText.trim();
          }
        }
      });

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
            print('❌ Errore nello scraping: $e');
            return shelf.Response.internalServerError(body: 'Errore: $e');
          }
        }
        return shelf.Response.notFound('Endpoint non trovato');
      });

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('✅ Server in ascolto su http://${server.address.host}:${server.port}');
}
