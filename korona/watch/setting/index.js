// Ustawienia w aplikacji Zepp: logowanie (to samo konto co w aplikacjach Na szczycie, Powrót i Zakupy na telefonie:
// zdobyte szczyty trafiają do aplikacji Na szczycie na telefonie).
// Hasło trafia do Side Service tylko na czas logowania i jest od razu usuwane.

const PASSWORD_MASK = "••••••••";

const CARD = {
  marginBottom: "12px",
  padding: "12px",
  border: "1px solid #eaeaea",
  borderRadius: "8px",
  backgroundColor: "white",
};

const HINT = { fontSize: "12px", color: "#888", marginTop: "6px" };

const BUTTON = {
  fontSize: "14px",
  borderRadius: "24px",
  color: "white",
  marginTop: "8px",
};

function readAuth(storage) {
  try {
    return JSON.parse(storage.getItem("auth") || "null");
  } catch (e) {
    return null;
  }
}

AppSettingsPage({
  build(props) {
    const storage = props.settingsStorage;
    const auth = readAuth(storage);
    const signUp = storage.getItem("loginMode") === "signup";
    const status = storage.getItem("authStatus") || (auth ? "Zalogowano jako " + auth.email : "Nie zalogowano");

    const header = [
      Text({ style: { fontSize: "18px", fontWeight: "bold", marginBottom: "8px" } }, ["Na szczycie – konto"]),
      Text({ style: { fontSize: "13px", color: "#555", marginBottom: "8px" } }, [
        "Zaloguj się tym samym kontem co w aplikacji Na szczycie (i Zakupy, Powrót) na telefonie. Zdobyte " +
          "szczyty pojawią się w telefonie (postęp list, mapa, historia) i będą bezpieczne po ponownej " +
          "instalacji aplikacji na zegarku. Bez logowania wszystko działa tylko na zegarku.",
      ]),
      Text({ style: { fontSize: "14px", color: auth ? "#2e7d32" : "#555", marginBottom: "12px" } }, [status]),
    ];

    if (auth) {
      return View({ style: { padding: "12px 20px" } }, [
        ...header,
        Text({ style: HINT }, [
          "Zegarek wysyła zdobycia po każdej zmianie, gdy otworzysz aplikację Na szczycie na zegarku " +
            "(telefon musi być połączony z zegarkiem).",
        ]),
        Button({
          label: "Wyloguj",
          style: { ...BUTTON, background: "#888" },
          onClick: () => {
            storage.removeItem("auth");
            storage.setItem("authStatus", "Wylogowano");
          },
        }),
      ]);
    }

    return View({ style: { padding: "12px 20px" } }, [
      ...header,
      View({ style: CARD }, [
        TextInput({
          label: "E-mail",
          value: storage.getItem("email") || "",
          subStyle: { color: "#333", fontSize: "14px" },
          onChange: (val) => storage.setItem("email", String(val || "").trim()),
        }),
      ]),
      View({ style: CARD }, [
        TextInput({
          label: signUp ? "Nowe hasło (min. 6 znaków)" : "Hasło",
          value: storage.getItem("password") ? PASSWORD_MASK : "",
          subStyle: { color: "#333", fontSize: "14px" },
          onChange: (val) => {
            if (val && val !== PASSWORD_MASK) storage.setItem("password", String(val));
          },
        }),
        Text({ style: HINT }, [
          "Hasło jest widoczne podczas wpisywania. Służy tylko do zalogowania i nie jest zapisywane.",
        ]),
      ]),
      Button({
        label: signUp ? "Załóż konto" : "Zaloguj",
        style: { ...BUTTON, background: "#2e7d32" },
        onClick: () => storage.setItem("loginRequest", String(Date.now())),
      }),
      Button({
        label: signUp ? "Mam już konto – logowanie" : "Nie mam konta – załóż je",
        style: { ...BUTTON, background: "#888" },
        onClick: () => storage.setItem("loginMode", signUp ? "login" : "signup"),
      }),
      Text({ style: { ...HINT, marginTop: "16px" } }, [
        "Jeśli logowanie nie rusza, otwórz aplikację Na szczycie na zegarku.",
      ]),
    ]);
  },
});
