# TP Mini-Discord — Client 

## Lancer le client

```bash
cd client
iex -S mix
```

Puis dans `iex` :

```elixir
MiniDiscord.Client.start("localhost", 4040)
# ou avec un tunnel bore :
MiniDiscord.Client.start("bore.pub", 32140)
```

---

## Fonctionnalités implémentées

### 1. Client de base

Le module `MiniDiscord.Client` implémente :

- **`start/2`** — point d'entrée, lance la connexion puis les deux boucles.
- **`rencontre/1`** — gère le handshake initial : réception du message de bienvenue, saisie du pseudo, choix du salon.
- **`receive_loop/3`** — boucle bloquante qui lit les messages entrants et les affiche.
- **`send_loop/1`** — boucle qui lit la saisie clavier et envoie les messages au serveur.

Les deux boucles tournent en parallèle grâce à `Task.async` / `Task.await`.

### 2. Robustesse

#### 2.1 — Reconnexion automatique

La fonction `connect_with_retry/3` retente la connexion toutes les 2 secondes en cas d'échec, en affichant le numéro de tentative.

#### 2.2 — Reconnexion depuis la réception

Quand `receive_loop` détecte une déconnexion (`{:error, reason}`), elle ferme proprement la socket avec `:gen_tcp.close/1` puis rappelle `connect_with_retry` pour rétablir la connexion sans action de l'utilisateur.

#### 2.3 — Robustesse OTP (réponse à la question)

Notre approche manuelle de reconnexion fonctionne, mais elle a une limite : si `send_loop` plante avant `receive_loop`, rien ne le redémarre. Avec OTP (un `Supervisor` + `GenServer`), tout l'arbre de processus serait surveillé et redémarré automatiquement selon une stratégie définie (`:one_for_one`, `:one_for_all`…). Cela évite aussi le problème du `send_loop` orphelin qui continuerait d'écrire sur une socket fermée.

### 2.4 — Validation des messages

La fonction `valider_message/1` rejette les messages :
- **vides** (après `String.trim`)
- **trop longs** (> 500 caractères)
- **contenant des caractères interdits** : `\ < > | " '`

Elle retourne `{:ok, msg}` ou `{:error, raison}` selon le cas.

### 2.5 — Cryptographie AES-256-CTR

Le module utilise `:crypto.crypto_one_time/5` pour chiffrer et déchiffrer les messages.

- Un vecteur d'initialisation (IV) de 16 octets est généré aléatoirement pour chaque message.
- Le message chiffré est envoyé sous la forme `<<iv::16 octets>> <> <<message_chiffré>>`.
- Le déchiffrement extrait les 16 premiers octets comme IV puis déchiffre le reste.
- Le serveur et le client partagent la même clé `@cle` (AES 256 bits).

> **Note** : pour activer la crypto en production, il faut modifier `send_loop` pour appeler `chiffrer/1` et `receive_loop` pour appeler `dechiffrer/1`, et s'assurer que le serveur implémente le même mécanisme.

---

## Protocole de communication

Le protocole est basé sur des lignes terminées par `\r\n` (option `packet: :line`).

```
Serveur → Client  "Bienvenue sur MiniDiscord!\r\n"
Serveur → Client  "Entre ton pseudo : "       (sans \n, bufferisé)
Client  → Serveur "<pseudo>\r\n"
Serveur → Client  "Salons disponibles : ...\r\n"
Serveur → Client  "Rejoins un salon : "        (sans \n, bufferisé)
Client  → Serveur "<salon>\r\n"
Serveur → Client  "Tu es dans #<salon>...\r\n"
Serveur → Client  "💡 Commandes : /list /join /quit\r\n"
--- échanges de messages ---
```
