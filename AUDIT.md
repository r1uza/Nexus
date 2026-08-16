# Audit delle sorgenti SF

Data audit: 17 agosto 2026. Cartelle esaminate in sola lettura:
`ECO`, `UVO`, `EVE`, `UGAI`, `NEXUS` sul Desktop dell'utente.

## Esito sintetico

| Progetto | Inventario | Gate eseguito | Esito operativo |
|---|---:|---|---|
| ECO 0.32.0 | 502 file, 446 Java | verifier root + suite Java | root `PASS`; suite bloccata da command line troppo lunga |
| UVO 0.32.0 | 1.114 file, 782 Dart | verifier + Flutter analyze | manifest `FAIL`; analyze 311 diagnostiche con errori bloccanti |
| EVE 0.22.0 | 543 file, 410 Java | verifier repository | manifest/seal/dist `PASS`; compilazione bloccata su Windows da command line troppo lunga |
| UGAI 1.0.0 | 997 file, 823 Java | scan boundary + build | scan `PASS`; build `FAIL` per batching `xargs` non portabile |
| NEXUS 0.27.0 | 544 file, 325 Dart | verifier + Dart analyze | manifest `FAIL`; 224 diagnostiche; nessun entry point di servizio |

L'host dell'audit disponeva di Python 3.12, Dart 3.12.2, Flutter 3.44.8 e
JDK 17 nel `PATH`. È stato poi individuato il JDK 25 di Android Studio, usato
con `--release 21`, e Git Bash fuori dal `PATH`. Docker non era disponibile.

## Riscontri per progetto

### ECO

- Il verifier root passa.
- La suite completa verifica il seal, ma la compilazione si ferma subito perché
  Git Bash non riesce a invocare `javac` con tutti i 446 sorgenti:
  `Argument list too long`. È un difetto di portabilità del gate; un argfile
  `@sources.txt` lo eliminerebbe.
- La separazione tra authorization, planning ed execution è chiara e fail-closed.
- Il progetto dichiara correttamente `HOST EXECUTION = false`: il JAR non ha
  `Main-Class` e non contiene un adapter host reale.
- È quindi una buona libreria di contratti operativi, non un servizio avviabile.

### UVO

- Il manifest attende 1.100 file nella foundation, ma ne trova 1.104. Gli extra
  sono `pubspec.lock` e tre file `.dart_tool`; il verifier non li esclude.
- `flutter analyze` restituisce 311 diagnostiche. Tra gli errori bloccanti:
  import host Android/desktop/web non risolti, simboli host mancanti, getter
  `permitsSuccessor` assente e import inutilizzati trattati come errori.
- Il repository stesso dichiara correttamente host build e artifact publishable
  come `BLOCKED`.

### EVE

- Manifest repository, riferimento al seal e hash degli artifact passano.
- Il verifier Windows arriva alla compilazione, poi Python fallisce con
  `WinError 206`: l'elenco dei sorgenti viene passato direttamente a `javac` e
  supera il limite della command line. Un argfile `@sources.txt` renderebbe il
  gate portabile.
- Anche eliminato questo limite, l'host corrente ha JDK 17 e non il JDK 21
  richiesto.

### UGAI

- È il riferimento più operativo: espone un vero `UgaiHttpServer`, un modulo
  Java, sito, Dockerfile, Compose, runbook, backup/restore e gate di sicurezza.
- Include un percorso ECO innocuo (`authorized local echo`) e separa endpoint
  pubblici dal control plane autenticato.
- I 27 scan statici/boundary invocati da `scripts/verify.sh` passano, inclusi
  foundation seal, forbidden API, secret scan e operational authority.
- La compilazione non passa. `find ... | xargs javac` viene spezzato in più
  invocazioni su Windows; i batch non includono nel classpath le classi già
  prodotte e generano 1.089 errori `cannot find symbol`/package mancanti. Il
  gate deve compilare tutti i sorgenti con un argfile oppure aggiungere l'output
  al classpath prima che la suite possa attestare il runtime.
- Docker packaging e deployment non sono stati eseguiti perché Docker non è
  installato.
- I file dichiarano esplicitamente che DNS/TLS e attivazione produzione sono
  ancora esterni e non verificati.

### NEXUS

- Il rilascio 0.27 è intenzionalmente un source release sigillato, non un
  package Dart pubblicabile né un servizio.
- Il manifest fallisce per tre file generati non esclusi: `pubspec.lock` e due
  file `.dart_tool`.
- `dart analyze` su Dart 3.12.2 restituisce 224 diagnostiche. Le famiglie
  bloccanti includono const generiche non più valide, costruttori `trusted`
  assenti, test non compatibili e import inutilizzati configurati come errori.
- Non esiste un comando `serve`, una API, un adapter di rete operativo o
  persistence su disco: il trasporto del baseline è soprattutto locale e
  contrattuale.

## Riscontri trasversali

1. Nessuna delle cinque cartelle contiene `LICENSE`, `LICENCE`, `COPYING` o
   `NOTICE`. Un repository senza concessione esplicita non è open source.
2. I seal SHA-256 dimostrano stabilità/integrità dei byte rispetto ai manifest,
   non autenticità dell'autore, sicurezza o operatività.
3. La scansione statica non ha trovato chiavi private o segreti letterali con i
   pattern controllati; questo non sostituisce un secret scanner dedicato in CI.
4. I repository sealed mescolano artefatti storici immutabili e metadati SDK
   generati. I verifier devono ignorare esplicitamente `.dart_tool`, lockfile e
   output di build oppure eseguirsi su una copia pulita.
5. Mancano prove riproducibili condivise tra sistemi: UVO/NEXUS usano Dart,
   ECO/EVE/UGAI Java 21, ma non esiste un unico gate di compatibilità end-to-end.

## Decisioni applicate a NEXUS.sf

- repository nuovo: nessun seal legacy è stato modificato o falsamente
  promosso;
- Apache-2.0 esplicita e perimetro open-core documentato;
- Dart puro, zero dipendenze runtime, compatibile con l'SDK disponibile;
- CLI, HTTP server, Docker e Compose reali;
- routing esatto con rifiuto delle ambiguità;
- token admin obbligatorio fuori dal loopback;
- ticket `execute.*` monouso, capability-bound, target-bound e con TTL massimo;
- trasporto HTTP con hostname allowlist, redirect disabilitati e limiti di
  richiesta/risposta;
- audit JSONL append-only senza payload o ticket;
- test negativi per auth, replay, ambiguità, SSRF e leakage dei trace.

## Rischi residui dichiarati

- Il core è single-process e la registry è in memoria; i nodi esterni vanno
  registrati dopo ogni restart.
- L'idempotenza è limitata alla vita del processo.
- Il token admin è un controllo single-role, non RBAC/SSO.
- JSONL non fornisce consenso distribuito né tamper evidence crittografica.
- Il trasporto HTTP non gestisce credenziali downstream; usare un sidecar o una
  implementazione del port di trasporto.
- TLS, reverse proxy, deployment reale e alta disponibilità restano responsabilità
  dell'operatore e non sono dichiarati verificati.
