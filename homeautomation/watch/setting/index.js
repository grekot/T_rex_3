// Ustawienia w aplikacji Zepp: logowanie tym samym kontem, którym termostat jest podłączony do chmury
// (to samo co w aplikacji HomeAutomation na telefonie, Zakupach i Na szczycie).
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

function readHomes(storage) {
  try {
    const homes = JSON.parse(storage.getItem("homes") || "[]");
    return Array.isArray(homes) ? homes : [];
  } catch (e) {
    return [];
  }
}

// Kilka domów (API.md pkt 12): który pokazuje zegarek. Listę zapisuje Side Service po otwarciu
// aplikacji na zegarku; bez wyboru - pierwszy dom.
function homeChoice(storage) {
  const homes = readHomes(storage);
  if (homes.length < 2) return [];
  const chosen = homes.some((h) => h.id === storage.getItem("homeId")) ? storage.getItem("homeId") : homes[0].id;
  return [
    View({ style: CARD }, [
      Text({ style: { fontSize: "14px", fontWeight: "bold", marginBottom: "4px" } }, ["Dom na zegarku"]),
      ...homes.map((h) =>
        Button({
          label: (h.id === chosen ? "✓ " : "") + (h.name || h.id),
          style: { ...BUTTON, background: h.id === chosen ? "#2e7d32" : "#888" },
          onClick: () => storage.setItem("homeId", h.id),
        })
      ),
    ]),
  ];
}

AppSettingsPage({
  build(props) {
    const storage = props.settingsStorage;
    const auth = readAuth(storage);
    const status = storage.getItem("authStatus") || (auth ? "Zalogowano jako " + auth.email : "Nie zalogowano");

    const header = [
      Text({ style: { fontSize: "18px", fontWeight: "bold", marginBottom: "8px" } }, ["Dom – konto"]),
      Text({ style: { fontSize: "13px", color: "#555", marginBottom: "8px" } }, [
        "Zaloguj się kontem, którym urządzenia domu są połączone z chmurą (to samo co w aplikacji HomeAutomation " +
          "na telefonie, Zakupach i Na szczycie). Zegarek pokazuje urządzenia, zmienia nastawę termostatu i włącza światła przez " +
          "internet, także spoza domu.",
      ]),
      Text({ style: { fontSize: "14px", color: auth ? "#2e7d32" : "#555", marginBottom: "12px" } }, [status]),
    ];

    if (auth) {
      return View({ style: { padding: "12px 20px" } }, [
        ...header,
        ...homeChoice(storage),
        Text({ style: HINT }, [
          "Zegarek odświeża stan co kilka sekund tylko wtedy, gdy aplikacja Dom jest na nim otwarta " +
            "(telefon musi być połączony z zegarkiem i mieć internet).",
        ]),
        Text({ style: HINT }, [
          "Kafelki na zegarku układasz w aplikacji HomeAutomation na telefonie, na ekranie „Zegarek” " +
            "(zegarek zgłasza się tam sam po pierwszym otwarciu aplikacji Dom). Bez ułożonego pulpitu " +
            "zegarek pokazuje wszystkie urządzenia, do których masz dostęp.",
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
          label: "Hasło",
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
        label: "Zaloguj",
        style: { ...BUTTON, background: "#2e7d32" },
        onClick: () => storage.setItem("loginRequest", String(Date.now())),
      }),
      Text({ style: { ...HINT, marginTop: "16px" } }, [
        "Jeśli logowanie nie rusza, otwórz aplikację Dom na zegarku.",
      ]),
    ]);
  },
});
