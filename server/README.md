# MiniDiscord

### Q1. Pourquoi utilise-t-on Process.monitor/1 dans handle_call({:rejoindre}) ?

Quand un client rejoint un salon, on monitore son PID pour être notifié s'il meurt.
Si le client se déconnecte brutalement (crash, coupure réseau), il ne peut pas appeler quitter/2 lui-même.
Grâce au monitor, le salon reçoit automatiquement un message {:DOWN, ...} et peut retirer le client de sa liste tout seul.

### Q2. Que se passe-t-il si on n'implémente pas handle_info({:DOWN, ...}) ?

Les PIDs des clients morts restent dans state.clients indéfiniment.
À chaque broadcast, on essaie d'envoyer des messages à des processus qui n'existent plus.
Elixir ne plante pas pour autant (send vers un PID mort est toléré), mais la liste grossit sans jamais se vider,
ce qui est une fuite mémoire. Sur le long terme ça dégrade les performances.

### Q3. Quelle est la différence entre handle_call et handle_cast ? Pourquoi broadcast est un cast ?

handle_call est synchrone : le processus appelant attend la réponse avant de continuer.
handle_cast est asynchrone : l'appelant envoie le message et repart immédiatement sans attendre.

broadcast est un cast parce qu'on s'en fiche de savoir quand exactement les clients ont reçu le message.
On envoie et on passe à la suite. Si c'était un call, chaque envoi de message bloquerait l'expéditeur
jusqu'à ce que le salon ait fini de broadcaster à tout le monde, ce qui serait inutile et lent.

### Q4. Le salon redémarre-t-il après le kill ? Pourquoi ?

Oui, le salon redémarre automatiquement.
C'est le DynamicSupervisor avec la stratégie :one_for_one qui s'en charge.
Quand un processus enfant meurt de manière anormale (ce que :kill provoque),
le superviseur le redémarre selon sa politique.
Par contre le salon repart avec un état vide, donc les clients connectés perdent leur session
et doivent se reconnecter.

### Q5. Quelle est la différence entre :one_for_one et :one_for_all ?

:one_for_one : si un enfant plante, seul lui est redémarré. Les autres continuent normalement.

:one_for_all : si un enfant plante, tous les enfants sont arrêtés puis redémarrés ensemble.
C'est utile quand les processus sont dépendants les uns des autres et ne peuvent pas fonctionner
si l'un d'eux est absent.

Dans notre cas :one_for_one est le bon choix. Si le salon "blagues" plante,
le salon "general" n'a aucune raison d'être redémarré aussi.