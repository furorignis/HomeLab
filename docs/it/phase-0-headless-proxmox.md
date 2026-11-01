# Fase 0 – Host Proxmox senza monitor

*Ottobre 2026 · Proxmox VE 9.2 · [English version](../en/phase-0-headless-proxmox.md)*

**In breve** – Un host Proxmox VE gestito solo dalla mia postazione (interfaccia web e SSH), con SSH solo a chiave, firmware impostato per funzionare senza nessuno davanti e una procedura di emergenza provata prima che qualcosa ne dipendesse. In seguito l'host è diventato il router di casa, e "deve ripartire da solo" ha smesso di essere un optional.

## Obiettivo

Tenere il server in un angolo senza monitor, tastiera né mouse. Ogni attività ordinaria si fa da remoto; l'accesso fisico serve solo per le emergenze, pianificate in anticipo.

## Hardware

| Componente | Modello |
|---|---|
| CPU | AMD Ryzen 5 9600X (6 core / 12 thread) |
| RAM | 32 GB DDR5 |
| Disco di sistema | NVMe da 256 GB |
| Disco dati | HDD 2,5" da 1 TB, recuperato da un portatile |
| Rete | Realtek 2,5 GbE integrata (gestione) + scheda Intel i226-V a due porte, riservata alla VM router (Fase 2) |

## Cosa ho costruito e perché

- **Proxmox VE sull'NVMe, ext4.** Un solo disco e nessuna ridondanza da gestire: ext4 è la scelta più semplice e non lascia una cache ZFS (ARC) da mettere nel conto su una macchina da 32 GB che farà girare anche un router e le prove del SIEM.
- **Indirizzo fisso e dominio riservato.** `192.168.178.3`, hostname `miniserver.home.arpa` (`home.arpa` è riservato alle reti domestiche, RFC 8375). Gli indirizzi fissi sull'host e sulla mia postazione lasciano l'hypervisor raggiungibile anche quando il DHCP o la VM router sono giù.
- **Canale di aggiornamento gratuito.** Repository enterprise disattivati, `pve-no-subscription` attivo. Aggiornamenti sempre con `apt full-upgrade`: un semplice `apt upgrade` può lasciare Proxmox aggiornato a metà. Il popup dell'abbonamento resta: gli script che lo tolgono modificano file di Proxmox come root e vengono sovrascritti a ogni aggiornamento.
- **SSH solo con chiave.**
  - Prima del primo accesso ho confrontato l'impronta ED25519 dell'host con quella mostrata sulla console del server, invece di accettarla alla cieca.
  - Chiave ed25519 con passphrase, ricifrata con 100 giri di derivazione (`ssh-keygen -p -a 100`) per rallentare chi prova a indovinarla offline.
  - Hardening in un file a parte, `/etc/ssh/sshd_config.d/10-hardening.conf`: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`. Un file a parte sopravvive agli aggiornamenti dei pacchetti e si toglie con un comando. `sshd` tiene il primo valore che legge e l'`Include` sta in cima a `sshd_config`, quindi prevale sul `PermitRootLogin yes` predefinito: verificato con `sshd -T`, non dato per scontato.
  - Su Proxmox `/root/.ssh/authorized_keys` è un collegamento al filesystem del cluster: le chiavi si aggiungono con `ssh-copy-id`, senza mai sovrascriverlo.
- **Firmware per il funzionamento senza presidio.** Accensione al ritorno della corrente; nessuno stop "premi F1" sugli errori del POST; Fast Boot spento, così una tastiera USB funziona sempre al POST; avvio dall'NVMe per primo; IOMMU attivo per il passthrough delle schede di rete della Fase 2. Le impostazioni sono salvate in un profilo del BIOS, così un reset del CMOS non le annulla in silenzio.
- **Una procedura di emergenza provata.** Ordine dei test: ping, interfaccia web, SSH, console fisica, così so a che livello si è rotto qualcosa prima di toccare qualsiasi cosa. Ogni guasto (SSH giù, interfaccia web giù, configurazione di rete rotta, chiave persa, host che non parte) ha una riga con cosa fare. La Shell dell'interfaccia web passa da `pveproxy` sulla porta 8006, non da `sshd`, quindi una configurazione SSH sbagliata non può chiudermi fuori. La password di root è conservata anche offline: un password manager ospitato su questa macchina sarebbe irraggiungibile proprio quando la macchina va riparata.

## Cosa è andato storto e come l'ho risolto

**Un server senza monitor in attesa di F1.** Dopo uno spegnimento forzato l'host si è fermato su "POSTed in safe mode… press F1": bloccato, e invisibile senza monitor. L'attesa di F1 era ancora attiva, perché il mio primo test copriva uno spegnimento pulito e il ritorno della corrente, non uno spegnimento forzato. Ho disattivato *Wait For F1 If Error* e Fast Boot, ricontrollato tutte le impostazioni importanti dalle foto delle schermate del BIOS, salvato il profilo e fatto le prove che mancavano: uno spegnimento forzato e un'interruzione di corrente di più di 10 secondi. Lezione: provare i casi di guasto, non solo il percorso normale.

**Brevi cali di corrente.** Con un calo di pochi secondi la scheda madre non si accorge della mancanza di corrente, quindi "accensione al ritorno della corrente" non scatta e l'host resta spento; a volte il pulsante di accensione non risponde finché non si stacca la spina. Nessuna impostazione del BIOS lo risolve. La procedura di emergenza ha la soluzione manuale; quella vera è un piccolo UPS con NUT, impostato per togliere l'uscita per qualche secondo dopo lo spegnimento, così la scheda vede tornare la corrente.

**Tipo di terminale sconosciuto.** Il mio terminale (Ghostty) imposta `TERM=xterm-ghostty`, che il server non conosceva, e strumenti come `watch` non partivano. Risolto una volta per tutte installando la voce terminfo sul server: `infocmp -x xterm-ghostty | ssh miniserver -- tic -x -`.

## Come è stato verificato

- Interfaccia web e SSH dalla postazione; l'accesso con chiave compare nel log (`Accepted publickey`), un tentativo con password viene rifiutato (`Permission denied (publickey)`).
- Avvio senza monitor né tastiera, poi raggiungibile in rete.
- Spegnimento pulito, corrente tolta e rimessa: l'host riparte da solo. Dopo la correzione, anche uno spegnimento forzato e un'interruzione di corrente di più di 10 secondi.
- Percorsi della procedura di emergenza: Shell dell'interfaccia web senza SSH; accesso dalla console fisica con la password di root; chiavetta dell'installer, monitor e tastiera pronti.

## Ancora aperto

- **Autenticazione a due fattori sull'interfaccia web** (TOTP con codici di recupero). Rimandata finché l'interfaccia è raggiungibile solo dalla LAN; è un prerequisito della VPN (Fase 5). La 2FA di Proxmox protegge interfaccia web e API, non SSH né la console fisica.
- **UPS con NUT**, per i cali di corrente descritti sopra.

## Competenze

Hardening di Linux e SSH · amministrazione di Proxmox VE · configurazione del firmware per server senza presidio · scrittura e verifica di procedure operative
