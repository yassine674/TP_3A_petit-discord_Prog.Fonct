defmodule MiniDiscord.Client do

  # Clé AES partagée avec le serveur (section 2.5)
  # Générer une fois : :crypto.strong_rand_bytes(32) |> Base.encode16()
  # et coller la même valeur dans server/lib/client_handler.ex
  @cle Base.decode16!("4D696E6944697363636F72644B65793131313131313131313131313131313131")

  @doc """
  Point d'entrée principal du client.
  host : nom type 'bore.pub' ou 'localhost'
  port : entier ex: 4040
  """
  def start(host, port) do
    connect_with_retry(host, port, 1)
  end


  # ----------------------------------------------------------------
  # 2.1 — Reconnexion automatique
  # ----------------------------------------------------------------

  defp connect_with_retry(host, port, attempt) do
    # Connecter la socket avec les bonnes options
    case :gen_tcp.connect(String.to_charlist(host), port,
           [:binary, packet: :line, active: false]) do

      {:ok, socket} ->
        # Handshake : pseudo + salon
        rencontre(socket)

        # Lancer receiver et sender en parallèle
        t1 = Task.async(fn -> receive_loop(socket, host, port) end)
        t2 = Task.async(fn -> send_loop(socket) end)

        # Attendre les deux tâches indéfiniment
        Task.await(t1, :infinity)
        Task.await(t2, :infinity)

      {:error, reason} ->
        IO.puts("Tentative #{attempt} échouée : #{reason}")
        :timer.sleep(2000)
        connect_with_retry(host, port, attempt + 1)
    end
  end


  # ----------------------------------------------------------------
  # Handshake initial : pseudo et choix du salon
  # ----------------------------------------------------------------

  defp rencontre(socket) do
    # Lire et afficher le message de bienvenue du serveur
    recv_print(socket)

    # Demander le pseudo à l'utilisateur et l'envoyer
    # (le serveur a envoyé "Entre ton pseudo : " sans \n, il reste
    #  dans le buffer et sera affiché avec le prochain recv_print)
    pseudo = IO.gets("Ton pseudo : ") |> String.trim()
    :gen_tcp.send(socket, pseudo <> "\r\n")

    # Lire la liste des salons (+ le prompt pseudo bufferisé)
    recv_print(socket)

    # Demander le salon et l'envoyer
    salon = IO.gets("Salon à rejoindre : ") |> String.trim()
    :gen_tcp.send(socket, salon <> "\r\n")

    # Lire la confirmation "Tu es dans #..."
    recv_print(socket)

    # Lire le message d'aide sur les commandes
    recv_print(socket)
  end


  # ----------------------------------------------------------------
  # 2.2 — Boucle de réception avec reconnexion automatique
  # ----------------------------------------------------------------

  defp receive_loop(socket, host, port) do
    # Bloquant jusqu'à réception d'un message
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} ->
        IO.write(msg)
        receive_loop(socket, host, port)

      {:error, reason} ->
        IO.puts("\nConnexion perdue (#{reason}). Reconnexion...")
        # Fermer proprement la socket avant de retenter
        :gen_tcp.close(socket)
        connect_with_retry(host, port, 1)
    end
  end


  # ----------------------------------------------------------------
  # Boucle d'envoi
  # ----------------------------------------------------------------

  defp send_loop(socket) do
    # Lire depuis le clavier
    msg = IO.gets("")

    # Valider avant d'envoyer
    case valider_message(msg) do
      {:ok, msg_valide} ->
        :gen_tcp.send(socket, msg_valide)

      {:error, raison} ->
        IO.puts("⚠  #{raison}")
    end

    send_loop(socket)
  end


  # ----------------------------------------------------------------
  # Helper : recevoir une ligne et l'afficher
  # ----------------------------------------------------------------

  defp recv_print(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, msg} -> IO.write(msg)
      {:error, _} -> :ok
    end
  end


  # ----------------------------------------------------------------
  # 2.4 — Validation des messages
  # ----------------------------------------------------------------

  @doc """
  Vérifie qu'un message est correct avant de l'envoyer.
  Retourne {:ok, msg} ou {:error, raison}.
  """
  def valider_message(msg) do
    msg = String.trim(msg)

    cond do
      msg == "" ->
        {:error, "Message vide"}

      String.length(msg) > 500 ->
        {:error, "Message trop long (max 500 chars)"}

      String.match?(msg, ~r/[\\<>\|"']/) ->
        {:error, "Message contient des caractères interdits (\\ < > | \" ')"}

      true ->
        {:ok, msg <> "\r\n"}
    end
  end


  # ----------------------------------------------------------------
  # 2.5 — Cryptographie AES-256-CTR
  # ----------------------------------------------------------------

  @doc """
  Chiffre un message avec la clé partagée.
  Format envoyé : <<iv:16 octets>> <> <<message chiffré>>
  """
  def chiffrer(msg) do
    iv    = :crypto.strong_rand_bytes(16)
    msg_c = :crypto.crypto_one_time(:aes_256_ctr, @cle, iv, msg, true)
    # On concatène l'IV au message chiffré
    iv <> msg_c
  end

  @doc """
  Déchiffre un message reçu.
  """
  def dechiffrer(msg_recu) do
    # Extraire les 16 premiers octets (IV) puis le reste (message chiffré)
    <<iv::binary-size(16), msg_chiffre::binary>> = msg_recu
    :crypto.crypto_one_time(:aes_256_ctr, @cle, iv, msg_chiffre, false)
  end

end