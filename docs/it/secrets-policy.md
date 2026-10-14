# Gestione dei segreti

Questo repository è pubblico. Questa pagina spiega come segreti e dati personali vengono tenuti fuori.

## Cosa non entra mai nel repository

- Password, chiavi private (SSH, WireGuard), token, credenziali del provider (PPPoE)
- La configurazione completa di OPNsense (`config.xml`): contiene hash delle password e chiavi
- IP pubblico, nome DDNS, indirizzi email personali
- Dettagli sui dispositivi di altre persone

Gli IP privati (192.168.x.x) sono pubblicati di proposito: non sono raggiungibili da internet.

## Difesa a strati

| Strato | Cosa fa | Dove |
|---|---|---|
| 1. `.gitignore` | Tiene fuori da git i file che contengono segreti | `.gitignore` |
| 2. gitleaks | Blocca i commit con formati di segreti noti (chiavi, token) | `.githooks/pre-commit` |
| 3. Denylist personale | Blocca i commit con valori personali che nessuna regola generica può conoscere (es. username del provider, nome del Wi-Fi) | `~/.config/homelab/denylist.txt`, fuori dal repo |
| 4. Controllo segreti di GitHub | Rete di sicurezza lato server | Previsto quando il repo diventa pubblico |

Scelte di progetto:

- **Fail-closed:** se manca gitleaks o la denylist, il commit si blocca. Un controllo che può spegnersi in silenzio non è un controllo.
- **Output oscurato:** i segreti trovati compaiono come `REDACTED`, quindi non finiscono nei log del terminale o nelle registrazioni dello schermo.
- **Solo il contenuto in staging:** lo script controlla esattamente ciò che sta per entrare nel commit, non la copia di lavoro.
- **Solo identificativi nella denylist:** mai password, altrimenti diventerebbe un nuovo file di segreti in chiaro.
- **Email dell'autore dei commit:** i commit usano l'indirizzo `noreply` di GitHub, perché le email degli autori sono pubbliche nella storia.

## File di esempio

Il file vero è ignorato; nel repo va una copia con valori finti (es. `wg0.conf` → `wg0.conf.example`).
I segnaposto vengono da intervalli riservati alla documentazione:

| Valore vero | Segnaposto |
|---|---|
| Password, chiave, token | `CHANGE_ME` |
| Email / dominio | `user@example.com`, `home.example.com` (RFC 2606) |
| IP pubblico | `203.0.113.10` (RFC 5737) |

## Configurazione dopo un clone

Un clone non attiva gli hook da solo:

```bash
sudo pacman -S gitleaks
git config core.hooksPath .githooks
mkdir -p ~/.config/homelab
touch ~/.config/homelab/denylist.txt
chmod 600 ~/.config/homelab/denylist.txt
```

## Come è stato testato

| Test | Atteso | Risultato |
|---|---|---|
| Token GitHub finto in un file in staging | Bloccato da gitleaks (`github-pat`) | Bloccato |
| Valore della denylist in un file in staging | Bloccato dal controllo denylist | Bloccato |
| File pulito, denylist mancante | Bloccato (fail-closed) | Bloccato |
| Commit pulito | Consentito | Consentito |
| Controllo di tutta la storia (`gitleaks git`) | Nessun risultato | Nessuna fuga trovata |

## Limiti noti

- `git commit --no-verify` salta tutti gli hook: mai usarlo in questo repo.
- Gli hook funzionano solo sulle macchine dove sono stati attivati.
- La denylist trova solo stringhe esatte (senza distinzione tra maiuscole e minuscole).
- gitleaks è considerato completo (solo correzioni di sicurezza). Betterleaks, degli stessi autori, sarà rivalutato quando la v2 sarà stabile.
