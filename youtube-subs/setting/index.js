// Settings App - formularz w aplikacji Zepp na telefonie.
// Wartości trafiają do settingsStorage, skąd czyta je Side Service.

const CARD_STYLE = {
  marginBottom: "16px",
  padding: "12px",
  border: "1px solid #eaeaea",
  borderRadius: "8px",
  backgroundColor: "white",
};

const HINT_STYLE = {
  fontSize: "12px",
  color: "#888",
  marginTop: "6px",
};

AppSettingsPage({
  build(props) {
    const storage = props.settingsStorage;
    const channelId = storage.getItem("channelId") || "";
    const apiKey = storage.getItem("apiKey") || "";

    const field = (label, key, value, hint) =>
      View({ style: CARD_STYLE }, [
        TextInput({
          label,
          value,
          subStyle: { color: "#333", fontSize: "14px" },
          onChange: (val) => storage.setItem(key, String(val || "").trim()),
        }),
        Text({ style: HINT_STYLE }, [hint]),
      ]);

    const status =
      channelId && apiKey
        ? "Ustawienia zapisane. Otwórz aplikację na zegarku i stuknij w ekran, aby odświeżyć."
        : "Wpisz ID kanału i klucz API, a potem uruchom aplikację na zegarku.";

    return View({ style: { padding: "12px 20px" } }, [
      Text({ style: { fontSize: "18px", fontWeight: "bold", marginBottom: "12px" } }, ["YouTube – subskrybenci"]),
      field(
        "ID kanału",
        "channelId",
        channelId,
        "Zaczyna się od UC i ma 24 znaki. YouTube Studio → Ustawienia → Kanał → Ustawienia zaawansowane."
      ),
      field(
        "Klucz API (YouTube Data API v3)",
        "apiKey",
        apiKey,
        "Google Cloud Console → Interfejsy API i usługi → Dane logowania."
      ),
      Text({ style: { fontSize: "13px", color: "#555" } }, [status]),
    ]);
  },
});
