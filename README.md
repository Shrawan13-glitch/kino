<div align="center">
  <br/>
  <img src="https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License"/>
  <img src="https://img.shields.io/badge/platform-Android-lightgrey?logo=android" alt="Platform"/>

  <br/>
  <br/>

  <h1>✨ ChatMorphism</h1>
  <p><strong>BYOK AI Chat — with on-device tool calling</strong></p>
  <p><em>Your keys. Your models. Your data. Agentic AI, entirely on your phone.</em></p>

  <br/>

  <!-- Navigation -->
  <p>
    <a href="#features">Features</a> •
    <a href="#tech-stack">Tech Stack</a> •
    <a href="#getting-started">Getting Started</a> •
    <a href="#configuration">Configuration</a> •
    <a href="#architecture">Architecture</a> •
    <a href="#screenshots">Screenshots</a> •
    <a href="#license">License</a>
  </p>

  <br/>
</div>

---

## 🚀 Features

<div>
  <table>
    <tr>
      <td width="50%">
        <h3>🔑 Bring Your Own Key</h3>
        <p>Connect to <strong>OpenRouter</strong> with your own API key. Access hundreds of models from OpenAI, Anthropic, Google, Meta, Mistral, and more — all through a single endpoint.</p>
      </td>
      <td width="50%">
        <h3>🛠️ On-Device Tool Calling</h3>
        <p>The only BYOK chat app with <strong>true agentic tool calling on-device</strong>. The model can search the web and fetch URLs — all executed locally on your phone.</p>
      </td>
    </tr>
    <tr>
      <td width="50%">
        <h3>💬 Streaming Responses</h3>
        <p>Real-time streaming with support for text chunks, reasoning/thought blocks, and tool call deltas. Watch the model think as it happens.</p>
      </td>
      <td width="50%">
        <h3>🌓 Dual Theme</h3>
        <p>Beautiful Material Design 3 UI with Dark, Light, and System-follow themes. Carefully crafted color schemes for a premium feel.</p>
      </td>
    </tr>
    <tr>
      <td width="50%">
        <h3>🔍 Multi-Engine Search</h3>
        <p>Built-in web search across <strong>DuckDuckGo</strong>, <strong>Mojeek</strong>, and <strong>Wikipedia</strong> — aggregated and de-duplicated. No external API keys needed.</p>
      </td>
      <td width="50%">
        <h3>📤 Share & Export</h3>
        <p>Copy responses as markdown, share them as rendered images, or export your entire chat history as JSON.</p>
      </td>
    </tr>
    <tr>
      <td width="50%">
        <h3>🧠 Custom Instructions</h3>
        <p>Two-tier prompting: app-level behavior prompt plus user-editable custom instructions. Full control over how the model responds.</p>
      </td>
      <td width="50%">
        <h3>📱 Native Flutter</h3>
        <p>Built with Flutter for smooth 60fps performance. Material Design 3 with dynamic color support and adaptive layouts.</p>
      </td>
    </tr>
  </table>
</div>

---

## 🧱 Tech Stack

<div>
  <table>
    <tr>
      <th>Layer</th>
      <th>Technology</th>
    </tr>
    <tr>
      <td>UI Framework</td>
      <td><img src="https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter&logoColor=white" height="20" alt="Flutter"/>  Material Design 3</td>
    </tr>
    <tr>
      <td>Language</td>
      <td><img src="https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white" height="20" alt="Dart"/>  Sealed classes, pattern matching</td>
    </tr>
    <tr>
      <td>State Management</td>
      <td><img src="https://img.shields.io/badge/Provider-6.x-blue" height="20" alt="Provider"/></td>
    </tr>
    <tr>
      <td>Local Database</td>
      <td><img src="https://img.shields.io/badge/SQLite-sqflite-blue?logo=sqlite&logoColor=white" height="20" alt="SQLite"/></td>
    </tr>
    <tr>
      <td>LLM Gateway</td>
      <td><img src="https://img.shields.io/badge/OpenRouter-API-ff6b6b" height="20" alt="OpenRouter"/></td>
    </tr>
    <tr>
      <td>Markdown Rendering</td>
      <td>gpt_markdown (streaming-aware)</td>
    </tr>
    <tr>
      <td>Search Engines</td>
      <td>DuckDuckGo · Mojeek · Wikipedia</td>
    </tr>
    <tr>
      <td>CI/CD</td>
      <td><img src="https://img.shields.io/badge/GitHub_Actions-2088FF?logo=github-actions&logoColor=white" height="20" alt="GitHub Actions"/></td>
    </tr>
  </table>
</div>

---

## 📦 Getting Started

### Prerequisites

- Flutter SDK (latest stable channel)
- Dart 3.12+
- An [OpenRouter](https://openrouter.ai) account and API key

### Installation

<pre>
# Clone the repository
git clone https://github.com/Shrawan13-glitch/chatmorphism.git
cd chatmorphism

# Install dependencies
flutter pub get

# Run the app
flutter run
</pre>

### Build APK

<pre>
flutter build apk --debug
</pre>

---

## ⚙️ Configuration

1. **Launch the app** and navigate to the **Models** screen from Settings.
2. **Enter your OpenRouter API key** and tap "Load" to fetch available models.
3. **Select a model** as your default, and optionally mark favorites.
4. **Start chatting** — the model can invoke web search and URL fetching tools on-device.

> **Note:** Your API key is stored locally in SQLite and never leaves your device. ChatMorphism does not collect any data.

---

## 🏗️ Architecture

<div>
  <pre align="center" style="background:#f6f8fa; padding:16px; border-radius:8px; font-size:13px;">
┌──────────────────────────────────────────────────────────┐
│                     Flutter UI Layer                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │  Home    │  │  Chat    │  │ Settings │  │  Models  │ │
│  │  Screen  │  │  Screen  │  │  Screen  │  │  Screen  │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
│       └──────────────┼─────────────┼──────────────┘       │
│                      ▼             ▼                       │
│  ┌─────────────────────────────────────────────────┐      │
│  │            Provider Layer (State Mgmt)          │      │
│  │  ┌───────────────┐      ┌──────────────────┐   │      │
│  │  │ ChatProvider   │      │ SettingsProvider │   │      │
│  │  └───────┬───────┘      └────────┬─────────┘   │      │
│  └──────────┼───────────────────────┼──────────────┘      │
│             ▼                       ▼                      │
│  ┌─────────────────────────────────────────────────┐      │
│  │              Service Layer                       │      │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │      │
│  │  │OpenRouter│  │  Search  │  │ WebFetch     │  │      │
│  │  │ Service  │  │  Service │  │ Service      │  │      │
│  │  └──────────┘  └──────────┘  └──────────────┘  │      │
│  └────────────────────┬────────────────────────────┘      │
│                       ▼                                    │
│  ┌─────────────────────────────────────────────────┐      │
│  │            Data Layer                            │      │
│  │  ┌────────────────┐  ┌──────────────────────┐  │      │
│  │  │ SQLite (sqflite)│  │  Generation Manager  │  │      │
│  │  └────────────────┘  └──────────────────────┘  │      │
│  └─────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────┘
  </pre>
</div>

### Key Flows

- **Chat Generation Loop:** User message → LLM request → Stream response → Tool call? → Execute on-device → Return to LLM → Final response
- **Tool Execution:** `web_search` queries 3 engines (DuckDuckGo, Mojeek, Wikipedia) in parallel, de-duplicates results; `fetch_url` fetches & cleans HTML to plain text
- **Data Persistence:** All chats, messages, and settings stored locally in SQLite with automatic migration support

---

## 📸 Screenshots

<div align="center">
  <p><em>Screenshots coming soon</em></p>
  <br/>
  <table>
    <tr>
      <td align="center"><strong>Chat View</strong></td>
      <td align="center"><strong>Settings</strong></td>
      <td align="center"><strong>Model Selection</strong></td>
    </tr>
    <tr>
      <td width="200" height="400" align="center" style="background:#f0f0f0; border-radius:12px;">
        <code>✦</code>
      </td>
      <td width="200" height="400" align="center" style="background:#f0f0f0; border-radius:12px;">
        <code>✦</code>
      </td>
      <td width="200" height="400" align="center" style="background:#f0f0f0; border-radius:12px;">
        <code>✦</code>
      </td>
    </tr>
  </table>
</div>

---

## 🧪 Testing

<pre>
flutter test
</pre>

---

## 🤝 Contributing

Contributions are welcome! This is an open-source project with a focus on privacy, on-device AI, and great UX.

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feat/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.

---

<div align="center">
  <br/>
  <p>
    Built with ❤️ for privacy-first, agentic AI on mobile.
    <br/>
    <sub>ChatMorphism — Your AI, your keys, your device.</sub>
  </p>
  <br/>
</div>
