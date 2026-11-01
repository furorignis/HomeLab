# Fase 1 – Backup

*Ottobre 2026 · Proxmox VE 9.2 · [English version](../en/phase-1-backups.md)*

**In breve** – Backup notturni di ogni VM e container su un disco separato, con conservazione, avvisi di errore su Telegram e una prova di ripristino che dimostra che i dati tornano, tutto pronto prima della prima modifica rischiosa. Lo storage è impostato in modo che un disco mancante faccia fallire i backup in modo evidente, invece di riempire in silenzio il disco di sistema.

## Obiettivo

Poter ripristinare qualsiasi VM o container in pochi minuti, prima di iniziare le modifiche che possono rompere qualcosa (la VM router, il passaggio della rete).

## Dischi

| Disco | Uso | Perché |
|---|---|---|
| NVMe da 256 GB | Proxmox, dischi di VM e container (pool LVM-thin) | I/O casuale veloce. Root e swap prendono la loro parte, quindi ai guest restano circa 140 GB, non 256 |
| HDD da 1 TB (2,5", 5400 giri, SMR) | backup, immagini ISO, dati | Va bene per le scritture sequenziali; con la tecnologia SMR è troppo lento per i dischi delle VM |

Prima di fidarmi di un disco usato ho letto i suoi dati SMART: stato PASSED, circa 9.000 ore di accensione, nessun settore riallocato, in attesa o non correggibile.

## Cosa ho costruito e perché

- **ext4 direttamente sull'HDD, come storage "Directory".** Niente LVM: se il server muore, il disco si collega a qualsiasi PC Linux e si legge così com'è. Formattato con `-m 0`: il 5 % che ext4 riserva a root sprecherebbe circa 46 GB su un disco solo per dati.
- **Un disco mancante non deve diventare un disco di sistema pieno.** Il guasto classico: l'HDD non è montato, il backup scrive nella cartella di mount vuota sul filesystem di root e l'NVMe si riempie. Lo storage ha `is_mountpoint yes`, quindi Proxmox lo considera non disponibile quando lì non è montato nulla; il disco è montato per UUID con `nofail`, così un disco guasto non blocca nemmeno l'avvio. Provato smontandolo: storage `inactive`, nessuna scrittura sull'NVMe.
- **Un solo job notturno per tutto.** Alle 03:00, tutti i guest (`all 1`, così le nuove VM e i nuovi container entrano da soli), compressione zstd. **Modalità snapshot**, non stop: quando il router è una VM, la modalità stop toglierebbe internet ogni notte.
- **Conservazione:** 7 giornalieri, 4 settimanali, 3 mensili. I backup manuali importanti (per esempio quello subito dopo il passaggio della rete) sono *protetti*, così la rotazione non li cancella mai.
- **Avvisi solo quando qualcosa non va.** Le notifiche di Proxmox arrivano a un bot Telegram tramite webhook, con un filtro solo per avvisi ed errori: nessun messaggio per un backup riuscito, così un messaggio vuol dire sempre che c'è da intervenire. La posta locale a root è disattivata: senza un server SMTP produceva solo rumore ("Undelivered Mail"). Il token del bot sta nell'archivio dei segreti di Proxmox, mai in questo repository.

## Cosa è andato storto e come l'ho risolto

**La conservazione non contava quello che pensavo.** Dopo diversi backup di prova nello stesso giorno ne era rimasto uno solo: `keep-daily` tiene l'*ultimo* backup di ogni giorno, non gli ultimi N backup. Comportamento corretto, ipotesi sbagliata. Ora leggo le regole di conservazione come "uno per periodo" e proteggo i backup manuali che voglio tenere.

**Due dettagli dei log che sembrano errori.** Il `TASK OK` finale non sta nel file `.log` accanto all'archivio: sta solo nel log dell'attività (*Datacenter → Backup*). E il log di un container spento dice `backup mode: stop` anche se il job chiede snapshot: un guest spento non ha nulla da fotografare. Nessuno dei due è un errore. I controlli di cui mi fido: lo stato dell'attività, più `zstd -t` sull'archivio.

**Il template sbagliato.** Scegliendo "il template Debian più recente" con `sort -V` è uscita la versione arm64, perché nell'ordinamento per versione `arm64` viene dopo `amd64`. Soluzione: filtrare prima l'architettura, poi ordinare.

**Ripartizionare un disco che conteneva già backup.** Più avanti ho diviso l'HDD in due, per riservare spazio ai dati dei servizi che passeranno su un secondo server. Cosa ho imparato: su Proxmox `parted` non è installato, `sgdisk` con `partx -u` sì; "il disco è vuoto" va verificato con `find` su tutto il punto di mount e non guardando la cartella dei backup, perché la cache dei template si riempie da sola; e la partizione che un giorno verrà eliminata va messa *per ultima*, così quella dei backup potrà ingrandirsi nello spazio liberato invece di dover rimpicciolire una partizione piena.

## Come è stato verificato

- **Prova di ripristino con un file-marcatore.** Un container di prova, acceso, con dentro un file-marcatore; backup in modalità snapshot (il log mostra il freeze e il thaw del filesystem); marcatore cancellato dall'originale; ripristino con `pct restore` su un nuovo ID. Il marcatore è ricomparso, il che dimostra che arriva dal backup, e l'originale non è mai stato toccato. Guest e archivi di prova eliminati alla fine. Il ripristino delle VM è stato provato più avanti con `qmrestore` (Fase 2).
- Integrità degli archivi con `zstd -t`.
- Avviso di errore provato con un guasto vero: HDD smontato, job avviato, messaggio Telegram ricevuto.
- Riavvio: il disco si monta da solo. `umount`: lo storage diventa inattivo e nessuna scrittura arriva all'NVMe.

## Ancora aperto

- **3-2-1.** Backup e dati condividono un disco nella stessa macchina: un HDD guasto, una sovratensione o un incendio li fanno perdere entrambi. È prevista una copia fuori sede.
- **L'hypervisor stesso.** `vzdump` salva i guest, non l'host. Script e unità systemd dell'host ora stanno in Git con un installer (`scripts/miniserver/`); per il resto, una reinstallazione segue la guida scritta.

## Competenze

Progettazione di backup e ripristino · politiche di conservazione · storage Linux (GPT, ext4, LVM-thin, fstab) · avvisi · verificare il ripristino invece di darlo per scontato
