const coreFeatures = [
  {
    title: "Custom battery alerts",
    description:
      "Get notified at any percentage — 3%, 20%, 80%, whatever matters to you — with a native-style alert instead of macOS's default pop-up.",
  },
  {
    title: "Battery health tracking",
    description:
      "Live health percentage, cycle count, and temperature, plus a heads-up before your battery needs service.",
  },
  {
    title: "Device monitoring",
    description:
      "AirPods, iPhone, iPad, Magic Mouse, keyboard, trackpad — every connected device's battery in one place.",
  },
  {
    title: "Charging protection",
    description:
      "Keep your battery in a healthy 50–80% band, or top up to 100% with one tap when you need the range.",
  },
  {
    title: "Energy insights",
    description:
      "See which apps are draining your battery right now, and look back over the last 24 hours, 7 days, or 30 days.",
  },
  {
    title: "Lives in the menu bar",
    description:
      "An iPhone-style battery icon that stays out of your way — under 0.1% CPU, everything processed locally.",
  },
];

const newFeatures = [
  {
    title: "Predictive alerts",
    description:
      "\"You'll be under 20% by the end of your 2pm meeting\" — lit reads your calendar so you're never caught out mid-call.",
  },
  {
    title: "Smart charging schedule",
    description:
      "lit learns your routine and only enforces the healthy charge band when it won't get in the way of your day.",
  },
  {
    title: "Long-term health trends",
    description:
      "Track degradation over months or years, and export a report — handy for warranty claims or resale.",
  },
  {
    title: "Any Bluetooth device",
    description:
      "Generic battery-service support means new peripherals just work, not just the devices on a hardcoded list.",
  },
];

// TODO: replace with the real GitHub repo URL once it's published.
const GITHUB_URL = "https://github.com/REPLACE_ME/lit";

export default function Home() {
  return (
    <div className="flex flex-col">
      <header className="flex items-center justify-between px-6 py-5 sm:px-10">
        <span className="text-lg font-semibold tracking-tight">lit</span>
        <a
          href={GITHUB_URL}
          className="rounded-full bg-foreground px-4 py-2 text-sm font-medium text-background transition hover:opacity-90"
        >
          GitHub
        </a>
      </header>

      <section className="mx-auto flex max-w-3xl flex-col items-center gap-6 px-6 py-20 text-center sm:py-28">
        <span className="rounded-full border border-black/10 px-3 py-1 text-xs text-foreground/60 dark:border-white/15">
          Free &amp; open source · macOS 14 and later
        </span>
        <h1 className="text-4xl font-semibold tracking-tight sm:text-6xl">
          Never get caught with a dead battery again
        </h1>
        <p className="max-w-xl text-balance text-base text-foreground/70 sm:text-lg">
          lit watches your Mac&rsquo;s battery so you don&rsquo;t have to — custom
          alerts, real health data, and charging habits that make the battery
          last longer. No account, no subscription, no catch.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
          <a
            href="#open-source"
            className="rounded-full bg-foreground px-6 py-3 text-sm font-medium text-background transition hover:opacity-90"
          >
            Download for Mac
          </a>
          <a
            href="#features"
            className="rounded-full border border-black/10 px-6 py-3 text-sm font-medium transition hover:bg-black/5 dark:border-white/15 dark:hover:bg-white/10"
          >
            See what it does
          </a>
        </div>
      </section>

      <section id="features" className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Everything your Mac&rsquo;s battery menu should&rsquo;ve had
        </h2>
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {coreFeatures.map((feature) => (
            <div
              key={feature.title}
              className="rounded-2xl border border-black/10 p-6 dark:border-white/10"
            >
              <h3 className="font-medium">{feature.title}</h3>
              <p className="mt-2 text-sm text-foreground/70">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          New in lit
        </h2>
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2">
          {newFeatures.map((feature) => (
            <div
              key={feature.title}
              className="rounded-2xl bg-black/[.03] p-6 dark:bg-white/[.05]"
            >
              <h3 className="font-medium">{feature.title}</h3>
              <p className="mt-2 text-sm text-foreground/70">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </section>

      <section
        id="open-source"
        className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20"
      >
        <div className="flex flex-col items-start gap-6 rounded-2xl border border-black/10 p-8 dark:border-white/10 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
              Free. Open source. Yours.
            </h2>
            <p className="mt-3 max-w-xl text-sm text-foreground/70">
              lit is MIT-licensed and built in the open. No trial, no license
              key, no paywalled features — clone it, build it, or grab a
              signed release. Everything runs locally; nothing phones home.
            </p>
          </div>
          <div className="flex shrink-0 flex-wrap gap-3">
            <a
              href={GITHUB_URL}
              className="rounded-full bg-foreground px-6 py-3 text-sm font-medium text-background transition hover:opacity-90"
            >
              View on GitHub
            </a>
            <a
              href={`${GITHUB_URL}/releases/latest`}
              className="rounded-full border border-black/10 px-6 py-3 text-sm font-medium transition hover:bg-black/5 dark:border-white/15 dark:hover:bg-white/10"
            >
              Latest release
            </a>
          </div>
        </div>
      </section>

      <footer className="mx-auto w-full max-w-5xl px-6 py-10 text-xs text-foreground/50">
        © {new Date().getFullYear()} lit. MIT licensed.
      </footer>
    </div>
  );
}
