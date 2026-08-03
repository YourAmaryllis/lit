import {
  Bell,
  HeartPulse,
  Bluetooth,
  BatteryCharging,
  BarChart3,
  LayoutGrid,
  Coffee,
  ShieldCheck,
  Focus,
  Presentation,
  Calendar,
  Smartphone,
  type LucideIcon,
} from "lucide-react";

const GITHUB_URL = "https://github.com/YourAmaryllis/lit";

type Feature = {
  icon: LucideIcon;
  title: string;
  description: string;
};

const shippedFeatures: Feature[] = [
  {
    icon: Bell,
    title: "Custom battery alerts",
    description:
      "Add any threshold — 3%, 20%, whatever matters to you — and get a real macOS notification the moment you cross it while unplugged.",
  },
  {
    icon: HeartPulse,
    title: "Battery health tracking",
    description:
      "Live health percentage, cycle count, and temperature, read straight from the same data macOS itself uses.",
  },
  {
    icon: Bluetooth,
    title: "Bluetooth device battery",
    description:
      "AirPods, Beats, Magic Mouse, keyboard, trackpad — anything reporting standard HID battery, listed with color-coded levels.",
  },
  {
    icon: BatteryCharging,
    title: "Lifecycle alerts",
    description:
      "Notified when you plug in, unplug, and when you hit 80% while charging — the cue to unplug for long-term battery health.",
  },
  {
    icon: LayoutGrid,
    title: "Themeable menu bar icon",
    description:
      "Icon + percentage, percentage only, or icon only — an iPhone-style battery glyph that color-codes itself as it drains.",
  },
  {
    icon: BarChart3,
    title: "Native & fast",
    description:
      "Real Swift, not Electron. Idles at roughly 0% CPU. Everything is computed on-device — nothing leaves your Mac.",
  },
];

const roadmapFeatures: Feature[] = [
  {
    icon: BatteryCharging,
    title: "Charge limiting / healthy band",
    description:
      "Cap charging at 50–80% to slow long-term degradation. Needs a privileged helper to write SMC charge-control keys, so it's a bigger, careful build.",
  },
  {
    icon: BarChart3,
    title: "Per-app energy insights",
    description:
      "See which apps are draining your battery right now, with 24h/7d/30d history. Likely needs the private IOReport framework — under investigation.",
  },
  {
    icon: Smartphone,
    title: "iPhone / iPad battery health",
    description:
      "Plug in your phone or tablet and see its health, cycle count, and temperature too, no extra app required.",
  },
  {
    icon: Calendar,
    title: "Predictive, calendar-aware alerts",
    description:
      "\"You'll be under 20% by the end of your 2pm meeting\" — reading your calendar so you're never caught out mid-call.",
  },
];

const useCases = [
  {
    icon: Coffee,
    title: "Working from a cafe with no outlet",
    description:
      "Set alerts at 10% and 5% so you know exactly how much runway you have left before you need to wrap up.",
  },
  {
    icon: ShieldCheck,
    title: "Keeping your battery healthy",
    description:
      "An 80% alert while charging is your cue to unplug — the single habit that does the most for long-term battery lifespan.",
  },
  {
    icon: Focus,
    title: "Deep focus work",
    description:
      "A 20% and 15% warning gives you time to save and wrap up before the screen goes dark mid-thought.",
  },
  {
    icon: Presentation,
    title: "Presentations and client calls",
    description:
      "Early alerts at 25% mean you're never scrambling for an outlet mid-pitch.",
  },
];

const faqs = [
  {
    question: "Is it actually free?",
    answer:
      "Yes — MIT licensed, no trial, no license key, no paywalled features. Build it from source or grab a signed release from GitHub.",
  },
  {
    question: "Does it collect any data?",
    answer:
      "No. Battery and device readings are computed on-device and never leave your Mac. There's no account, no analytics, no cloud sync.",
  },
  {
    question: "What macOS versions does it support?",
    answer: "macOS 14 and later, on both Apple Silicon and Intel.",
  },
  {
    question: "How is this different from the built-in battery menu?",
    answer:
      "Custom alert thresholds instead of one fixed low-battery warning, real health/cycle/temperature data, Bluetooth accessory battery levels in one place, and lifecycle alerts for healthier charging habits.",
  },
  {
    question: "Can I trust an open source battery app with system access?",
    answer:
      "Every line is public on GitHub — read it, build it yourself, or audit exactly what it does before you trust it with your Mac.",
  },
];

function FeatureCard({ feature, muted = false }: { feature: Feature; muted?: boolean }) {
  const Icon = feature.icon;
  return (
    <div
      className={`rounded-2xl border p-6 ${
        muted
          ? "border-black/10 bg-black/[.02] dark:border-white/10 dark:bg-white/[.03]"
          : "border-black/10 dark:border-white/10"
      }`}
    >
      <div className="flex h-9 w-9 items-center justify-center rounded-full bg-foreground/[.06] dark:bg-foreground/[.1]">
        <Icon className="h-4.5 w-4.5" strokeWidth={1.75} />
      </div>
      <h3 className="mt-4 font-medium">{feature.title}</h3>
      <p className="mt-2 text-sm text-foreground/70">{feature.description}</p>
    </div>
  );
}

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

      <section className="mx-auto w-full max-w-3xl px-6 pb-16 text-center sm:pb-20">
        <p className="text-balance text-lg text-foreground/60 sm:text-xl">
          macOS gives you <span className="text-foreground">one</span>{" "}
          low-battery warning, no health data, and no idea what&rsquo;s
          connected to your Mac or how much charge it has left. lit is the
          menu bar app that actually tells you what&rsquo;s going on.
        </p>
      </section>

      <section id="features" className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Everything your Mac&rsquo;s battery menu should&rsquo;ve had
        </h2>
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {shippedFeatures.map((feature) => (
            <FeatureCard key={feature.title} feature={feature} />
          ))}
        </div>
      </section>

      <section className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          On the roadmap
        </h2>
        <p className="mt-2 text-sm text-foreground/60">
          Being upfront: these aren&rsquo;t built yet. They&rsquo;re the harder,
          system-level pieces we&rsquo;re working through in the open.
        </p>
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2">
          {roadmapFeatures.map((feature) => (
            <FeatureCard key={feature.title} feature={feature} muted />
          ))}
        </div>
      </section>

      <section className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Built for how you actually work
        </h2>
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2">
          {useCases.map((useCase) => {
            const Icon = useCase.icon;
            return (
              <div key={useCase.title} className="flex gap-4">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-foreground/[.06] dark:bg-foreground/[.1]">
                  <Icon className="h-4.5 w-4.5" strokeWidth={1.75} />
                </div>
                <div>
                  <h3 className="font-medium">{useCase.title}</h3>
                  <p className="mt-1 text-sm text-foreground/70">
                    {useCase.description}
                  </p>
                </div>
              </div>
            );
          })}
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

      <section className="mx-auto w-full max-w-3xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Questions? We&rsquo;ve got answers.
        </h2>
        <div className="mt-8 divide-y divide-black/10 dark:divide-white/10">
          {faqs.map((faq) => (
            <div key={faq.question} className="py-5">
              <h3 className="font-medium">{faq.question}</h3>
              <p className="mt-2 text-sm text-foreground/70">{faq.answer}</p>
            </div>
          ))}
        </div>
      </section>

      <footer className="mx-auto w-full max-w-5xl px-6 py-10 text-xs text-foreground/50">
        © {new Date().getFullYear()} lit. MIT licensed.
      </footer>
    </div>
  );
}
