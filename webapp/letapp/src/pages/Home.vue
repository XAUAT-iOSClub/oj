<script setup lang="ts">
import { computed, markRaw, onMounted, ref } from "vue";
import { Icon } from "@iconify/vue";
import { useRouter } from "vue-router";
import { apiRequest, listMySubmissions, listFavorites } from "../services/api";
import { useAuthStore } from "../stores/auth";
import { formatDateTime as formatCSTDateTime } from "../utils/time";

const router = useRouter();
const terminalRef = ref<HTMLElement | null>(null);
const currentLanguage = ref("cpp");

const languages = markRaw([
  {
    name: "JavaScript",
    value: "javascript",
    icon: "vscode-icons:file-type-js-official",
  },
  {
    name: "Python",
    value: "python",
    icon: "vscode-icons:file-type-python",
  },
  {
    name: "Java",
    value: "java",
    icon: "vscode-icons:file-type-java",
  },
  {
    name: "C++",
    value: "cpp",
    icon: "vscode-icons:file-type-cpp",
  },
  {
    name: "Go",
    value: "go",
    icon: "vscode-icons:file-type-go",
  },
  {
    name: "Rust",
    value: "rust",
    icon: "vscode-icons:file-type-rust",
  },
  {
    name: "Swift",
    value: "swift",
    icon: "vscode-icons:file-type-swift",
  },
  {
    name: "Kotlin",
    value: "kotlin",
    icon: "vscode-icons:file-type-kotlin",
  },
]);

const codeSamples: Record<string, string> = {
  cpp: `<span class="code-directive">#include</span> <span class="code-muted">&lt;iostream&gt;</span>\n\n<span class="code-type">int</span> <span class="code-function">main</span>() {\n  <span class="code-object">std::cout</span> <span class="code-muted">&lt;&lt;</span> <span class="code-string">"Hello, Let Coding!"</span> <span class="code-muted">&lt;&lt;</span> <span class="code-string">'\\n'</span>;\n  <span class="code-keyword">return</span> <span class="code-number">0</span>;\n}`,
  python: `<span class="code-keyword">print</span>(<span class="code-string">"Hello, Let Coding!"</span>)`,
  javascript: `<span class="code-object">console</span>.<span class="code-function">log</span>(<span class="code-string">"Hello, Let Coding!"</span>);`,
  java: `<span class="code-keyword">public</span> <span class="code-type">class</span> <span class="code-function">Main</span> {\n  <span class="code-keyword">public</span> <span class="code-type">static void</span> <span class="code-function">main</span>(<span class="code-object">String</span>[] args) {\n    <span class="code-object">System.out</span>.<span class="code-function">println</span>(<span class="code-string">"Hello, Let Coding!"</span>);\n  }\n}`,
  go: `<span class="code-keyword">package</span> <span class="code-function">main</span>\n<span class="code-keyword">import</span> <span class="code-string">"fmt"</span>\n\n<span class="code-type">func</span> <span class="code-function">main</span>() {\n  <span class="code-object">fmt</span>.<span class="code-function">Println</span>(<span class="code-string">"Hello, Let Coding!"</span>)\n}`,
  rust: `<span class="code-type">fn</span> <span class="code-function">main</span>() {\n  <span class="code-object">println!</span>(<span class="code-string">"Hello, Let Coding!"</span>);\n}`,
  swift: `<span class="code-keyword">print</span>(<span class="code-string">"Hello, Let Coding!"</span>)`,
  kotlin: `<span class="code-type">fun</span> <span class="code-function">main</span>() {\n  <span class="code-object">println</span>(<span class="code-string">"Hello, Let Coding!"</span>)\n}`,
};

const extMap: Record<string, string> = {
  cpp: "cpp",
  python: "py",
  javascript: "js",
  java: "java",
  go: "go",
  rust: "rs",
  swift: "swift",
  kotlin: "kt",
};

const currentCode = computed(
  () => codeSamples[currentLanguage.value] || codeSamples.cpp,
);
const currentFileExt = computed(
  () => extMap[currentLanguage.value] || extMap.cpp,
);

const selectLanguage = (lang: { value: string }) => {
  currentLanguage.value = lang.value;
};

const handleTerminalClick = (event: MouseEvent) => {
  if ((event.target as HTMLElement).closest("button")) return;
  void router.push("/playground");
};

const handleTerminalKeydown = (event: KeyboardEvent) => {
  if (event.target !== event.currentTarget) return;
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    void router.push("/playground");
  }
};

// ===== 首页 Dashboard 数据 =====
const authStore = useAuthStore();
const dashboardLoading = ref(true);
const recentProblems = ref<any[]>([]);
const recentSubmissions = ref<any[]>([]);
const favoriteCount = ref(0);
const totalProblems = ref(0);
const submissionTotal = ref(0);
const acceptedCount = ref(0);
const solvedCount = ref(0);
const difficultyDist = ref({ easy: 0, mid: 0, hard: 0 });

const statusMeta: Record<string, { label: string; cls: string }> = {
  AC: { label: "通过", cls: "ui-badge-green" },
  WA: { label: "答案错误", cls: "ui-badge-red" },
  CE: { label: "编译错误", cls: "ui-badge-amber" },
  TLE: { label: "超时", cls: "ui-badge-amber" },
  RE: { label: "运行错误", cls: "ui-badge-red" },
  Running: { label: "判题中", cls: "ui-badge-blue" },
  Pending: { label: "排队中", cls: "ui-badge-slate" },
};
const statusLabel = (s: string) =>
  (statusMeta[s] ?? { label: s || "未知", cls: "ui-badge-slate" }).label;
const statusClass = (s: string) =>
  (statusMeta[s] ?? { label: "", cls: "ui-badge-slate" }).cls;

const formatRate = (accepted: number, submission: number) => {
  const a = Number(accepted) || 0;
  const b = Number(submission) || 0;
  if (!b) return "—";
  return `${Math.round((a / b) * 100)}%`;
};
const formatDateShort = (dateString: string | null) => {
  if (!dateString) return "—";
  return formatCSTDateTime(dateString, {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
};
const goProblem = (id: number) => void router.push(`/problems/${id}`);

const difficultyRows = computed(() => {
  const { easy, mid, hard } = difficultyDist.value;
  const total = easy + mid + hard || 1;
  return [
    { key: "easy", label: "简单", value: easy, pct: Math.round((easy / total) * 100), textClass: "text-emerald-600 dark:text-emerald-400", barClass: "bg-emerald-500" },
    { key: "mid", label: "中等", value: mid, pct: Math.round((mid / total) * 100), textClass: "text-amber-600 dark:text-amber-400", barClass: "bg-amber-500" },
    { key: "hard", label: "困难", value: hard, pct: Math.round((hard / total) * 100), textClass: "text-rose-600 dark:text-rose-400", barClass: "bg-rose-500" },
  ];
});

const loadDashboard = async () => {
  dashboardLoading.value = true;
  try {
    const probPromise = apiRequest<any>("/problems", { skipAuth: true }).catch(
      () => null,
    );
    const subPromise = authStore.isAuthenticated
      ? listMySubmissions(1, 8)
      : Promise.resolve(null);
    const favPromise = authStore.isAuthenticated
      ? listFavorites()
      : Promise.resolve(null);
    const [probRes, subRes, favRes] = await Promise.all([
      probPromise,
      subPromise,
      favPromise,
    ]);
    if (probRes) {
      const list = Array.isArray(probRes.data) ? probRes.data : [];
      totalProblems.value = Number(probRes.total) || list.length;
      recentProblems.value = list.slice(0, 8);
      let e = 0,
        m = 0,
        h = 0;
      list.forEach((p: any) => {
        const d = p.difficulty;
        if (d === "简单") e += 1;
        else if (d === "中等") m += 1;
        else if (d === "困难") h += 1;
      });
      difficultyDist.value = { easy: e, mid: m, hard: h };
    }
    if (subRes) {
      const subs = subRes.data ?? [];
      recentSubmissions.value = subs;
      submissionTotal.value = Number(subRes.total) || subs.length;
      const solved = new Set<number>();
      let ac = 0;
      subs.forEach((s: any) => {
        if (s.status === "AC") {
          ac += 1;
          if (s.problem_id != null) solved.add(s.problem_id);
        }
      });
      acceptedCount.value = ac;
      solvedCount.value = solved.size;
    }
    if (favRes) {
      favoriteCount.value = Array.isArray(favRes.data) ? favRes.data.length : 0;
    }
  } catch {
    // 仪表盘数据加载失败不影响主页展示
  } finally {
    dashboardLoading.value = false;
  }
};

onMounted(loadDashboard);
</script>

<template>
  <main class="home-shell">
    <section class="hero-section">
      <div class="hero-grid" aria-hidden="true"></div>
      <div class="hero-layout">
        <div class="hero-copy">
          <span class="code-mark mark-tag" aria-hidden="true">&lt;/&gt;</span>
          <span class="code-mark mark-brace" aria-hidden="true">{ }</span>
          <span class="code-mark mark-comment" aria-hidden="true">//</span>
          <span class="hero-label intro intro-label">
            <span class="status-dot"></span>
            Let Coding · 在线评测
          </span>

          <h1 class="hero-title">
            <span class="title-line intro intro-title-one">写代码</span>
            <span class="title-line title-accent intro intro-title-two">更加顺手</span>
          </h1>

          <p class="hero-desc intro intro-desc">
            在线编写、运行和提交代码，支持多语言判题。
          </p>

          <div class="hero-actions intro intro-actions">
            <button
              class="hero-button hero-primary"
              @click="router.push('/playground')"
            >
              <Icon icon="material-symbols:play-arrow" />
              <span>进入在线编辑器</span>
            </button>
            <button
              class="hero-button hero-secondary"
              @click="router.push('/learn')"
            >
              <Icon icon="material-symbols:school" />
              <span>查看学习资源</span>
            </button>
          </div>
        </div>

        <div
          ref="terminalRef"
          class="terminal-stage intro intro-terminal"
          role="link"
          tabindex="0"
          aria-label="进入在线编辑器"
          @click="handleTerminalClick"
          @keydown="handleTerminalKeydown"
        >
          <div class="terminal-frame">
            <div class="terminal-toolbar">
              <div class="window-controls" aria-hidden="true">
                <span></span><span></span><span></span>
              </div>
              <div class="file-path">playground/main.{{ currentFileExt }}</div>
              <Icon
                icon="material-symbols:terminal-rounded"
                class="toolbar-icon"
              />
            </div>

            <div class="terminal-workspace">
              <section class="code-panel">
                <div class="panel-heading">
                  <span><Icon icon="material-symbols:code" />Sample Code</span>
                </div>
                <div class="editor-body">
                  <div class="active-line" aria-hidden="true"></div>
                  <div class="line-numbers" aria-hidden="true">
                    <span v-for="line in 7" :key="line">{{ line }}</span>
                  </div>
                  <pre><code v-html="currentCode"></code></pre>
                </div>
              </section>

              <aside class="terminal-side">
                <section class="result-panel">
                  <div class="panel-heading">
                    <span>运行结果</span>
                  </div>
                  <div class="judge-timeline">
                    <div class="judge-status status-compiling">
                      <span></span>Compiling
                    </div>
                    <div class="judge-status status-running">
                      <span></span>Running
                    </div>
                    <div class="judge-status status-accepted">
                      <Icon
                        icon="material-symbols:check-circle-rounded"
                      />Accepted
                    </div>
                  </div>
                  <div class="preview-output">Hello, Let Coding!</div>
                </section>
              </aside>
            </div>

            <section class="language-panel">
              <div class="panel-heading">
                <span>支持语言</span>
              </div>
              <div class="language-grid">
                <button
                  v-for="language in languages"
                  :key="language.value"
                  type="button"
                  class="language-button"
                  :class="{ active: currentLanguage === language.value }"
                  :aria-label="language.name"
                  @click.stop="selectLanguage(language)"
                >
                  <Icon :icon="language.icon" />
                </button>
              </div>
            </section>
          </div>
        </div>
      </div>
    </section>

    <section class="home-dashboard border-t border-[#E2E8F0] py-6 dark:border-[#1E293B]">
      <div class="app-container">
        <div class="ui-card mb-4 flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
          <div class="flex items-center gap-3">
            <span class="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-[#EFF6FF] text-[#2563EB] dark:bg-[#172554] dark:text-[#60A5FA]"><Icon icon="material-symbols:menu-book-rounded" class="h-5 w-5" /></span>
            <div>
              <h2 class="ui-section-title leading-tight">{{ authStore.isAuthenticated ? (authStore.displayName || '同学') : '登录后开始刷题' }}</h2>
              <p class="text-xs text-[#64748B] dark:text-[#94A3B8]">{{ authStore.isAuthenticated ? '查看最近提交与学习进度' : '同步提交记录、收藏与学习进度' }}</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <router-link to="/problems" class="hero-dash-btn hero-dash-primary !px-3 !py-2 text-xs">
              <Icon icon="material-symbols:play-arrow-rounded" class="h-4 w-4" />
              开始刷题
            </router-link>
            <router-link to="/playground" class="hero-dash-btn hero-dash-secondary !px-3 !py-2 text-xs">
              <Icon icon="material-symbols:code-rounded" class="h-4 w-4" />
              打开编辑器
            </router-link>
            <router-link to="/contests" class="hero-dash-btn hero-dash-outline !px-3 !py-2 text-xs">
              <Icon icon="material-symbols:trophy-rounded" class="h-4 w-4" />
              查看比赛
            </router-link>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="ui-card flex items-center gap-2.5 p-3">
            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#F1F5F9] text-[#64748B] dark:bg-[#1E293B] dark:text-[#94A3B8]"><Icon icon="material-symbols:check-circle-rounded" class="h-4 w-4" /></span>
            <div class="min-w-0">
              <p class="truncate text-[11px] font-medium text-[#64748B] dark:text-[#94A3B8]">已解决</p>
              <p class="text-xl font-bold leading-tight">{{ dashboardLoading ? '—' : solvedCount }}</p>
            </div>
          </div>
          <div class="ui-card flex items-center gap-2.5 p-3">
            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#F1F5F9] text-[#64748B] dark:bg-[#1E293B] dark:text-[#94A3B8]"><Icon icon="material-symbols:history-rounded" class="h-4 w-4" /></span>
            <div class="min-w-0">
              <p class="truncate text-[11px] font-medium text-[#64748B] dark:text-[#94A3B8]">提交总数</p>
              <p class="text-xl font-bold leading-tight">{{ dashboardLoading ? '—' : submissionTotal }}</p>
            </div>
          </div>
          <div class="ui-card flex items-center gap-2.5 p-3">
            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#F1F5F9] text-[#64748B] dark:bg-[#1E293B] dark:text-[#94A3B8]"><Icon icon="material-symbols:star-rounded" class="h-4 w-4" /></span>
            <div class="min-w-0">
              <p class="truncate text-[11px] font-medium text-[#64748B] dark:text-[#94A3B8]">收藏</p>
              <p class="text-xl font-bold leading-tight">{{ dashboardLoading ? '—' : favoriteCount }}</p>
            </div>
          </div>
          <div class="ui-card flex items-center gap-2.5 p-3">
            <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#F1F5F9] text-[#64748B] dark:bg-[#1E293B] dark:text-[#94A3B8]"><Icon icon="material-symbols:library-books-rounded" class="h-4 w-4" /></span>
            <div class="min-w-0">
              <p class="truncate text-[11px] font-medium text-[#64748B] dark:text-[#94A3B8]">题库题量</p>
              <p class="text-xl font-bold leading-tight">{{ dashboardLoading ? '—' : totalProblems }}</p>
            </div>
          </div>
        </div>

        <div class="mt-4 grid gap-4 lg:grid-cols-2">
          <div class="ui-card p-4">
            <div class="mb-3 flex items-center justify-between">
              <h3 class="ui-section-title">继续学习</h3>
              <router-link to="/problems" class="text-xs font-medium text-[#2563EB] dark:text-[#60A5FA]">全部题目</router-link>
            </div>
            <div v-if="dashboardLoading" class="space-y-1.5">
              <div v-for="i in 6" :key="i" class="ui-skeleton h-9 rounded-lg"></div>
            </div>
            <div v-else-if="recentProblems.length" class="space-y-1">
              <router-link
                v-for="p in recentProblems"
                :key="p.id"
                :to="`/problems/${p.id}`"
                class="flex items-center gap-2.5 rounded-lg border border-[#E2E8F0] px-2.5 py-2 text-sm transition-colors hover:border-[#CBD5E1] hover:bg-[#F8FAFC] dark:border-[#1E293B] dark:hover:border-[#334155] dark:hover:bg-[#172554]"
              >
                <span class="min-w-0 flex-1 truncate font-bold text-[#1E293B] dark:text-[#E5E7EB]">{{ p.title }}</span>
                <span v-if="p.difficulty" class="ui-diff text-[11px]" :class="p.difficulty === '简单' ? 'ui-diff-easy' : p.difficulty === '中等' ? 'ui-diff-mid' : 'ui-diff-hard'">{{ p.difficulty }}</span>
                <span class="shrink-0 text-[11px] text-[#64748B] dark:text-[#94A3B8]">通过率 {{ formatRate(p.accepted_count, p.submission_count) }}</span>
              </router-link>
            </div>
            <p v-else class="ui-empty">暂无题目</p>
          </div>

          <div class="ui-card p-4">
            <div class="mb-3 flex items-center justify-between">
              <h3 class="ui-section-title">最近活动</h3>
              <router-link to="/submissions" class="text-xs font-medium text-[#2563EB] dark:text-[#60A5FA]">全部记录</router-link>
            </div>
            <div v-if="dashboardLoading" class="space-y-1.5">
              <div v-for="i in 6" :key="i" class="ui-skeleton h-9 rounded-lg"></div>
            </div>
            <div v-else-if="recentSubmissions.length" class="space-y-1">
              <button
                v-for="s in recentSubmissions"
                :key="s.id"
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg border border-[#E2E8F0] px-2.5 py-2 text-left text-sm transition-colors hover:border-[#CBD5E1] hover:bg-[#F8FAFC] dark:border-[#1E293B] dark:hover:border-[#334155] dark:hover:bg-[#172554]"
                @click="goProblem(s.problem_id)"
              >
                <span class="ui-badge text-[11px]" :class="statusClass(s.status)">{{ statusLabel(s.status) }}</span>
                <span class="min-w-0 flex-1 truncate font-bold text-[#1E293B] dark:text-[#E5E7EB]">{{ s.problem_title }}</span>
                <span class="shrink-0 text-[11px] text-[#64748B] dark:text-[#94A3B8]">{{ formatDateShort(s.created_at) }}</span>
              </button>
            </div>
            <p v-else class="ui-empty">暂无提交记录</p>
          </div>
        </div>

        <div class="ui-card mt-4 p-4">
          <h3 class="ui-section-title mb-3">题库难度分布</h3>
          <div class="grid gap-3 sm:grid-cols-3">
            <div v-for="item in difficultyRows" :key="item.key" class="rounded-lg border border-[#E2E8F0] p-3 dark:border-[#1E293B]">
              <div class="flex items-center justify-between text-xs font-bold">
                <span :class="item.textClass">{{ item.label }}</span>
                <span class="text-[#64748B] dark:text-[#94A3B8]">{{ item.value }} 题</span>
              </div>
              <div class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-[#E2E8F0] dark:bg-[#1E293B]">
                <div class="h-full rounded-full" :class="item.barClass" :style="{ width: item.pct + '%' }"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

  </main>
</template>

<style scoped>
.home-shell {
  overflow: hidden;
  background: #eef2f5;
  color: #111827;
}
.hero-dash-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  padding: 0.6rem 1.2rem;
  border-radius: 0.5rem;
  font-size: 0.8125rem;
  font-weight: 600;
  transition:
    background-color 0.15s ease,
    border-color 0.15s ease,
    color 0.15s ease;
  cursor: pointer;
}
.hero-dash-primary {
  background: #2563EB;
  color: #fff;
}
.hero-dash-primary:hover {
  background: #1D4ED8;
}
.hero-dash-secondary {
  background: #EFF6FF;
  color: #2563EB;
  border: 1px solid #BFDBFE;
}
.hero-dash-secondary:hover {
  background: #DBEAFE;
  border-color: #93C5FD;
}
.hero-dash-outline {
  background: transparent;
  color: #475569;
  border: 1px solid #CBD5E1;
}
.hero-dash-outline:hover {
  background: #F8FAFC;
  border-color: #94A3B8;
  color: #1E293B;
}
.dark .hero-dash-secondary {
  background: #172554;
  color: #60A5FA;
  border-color: #1E3A5F;
}
.dark .hero-dash-secondary:hover {
  background: #1E3A5F;
  border-color: #2563EB;
}
.dark .hero-dash-outline {
  color: #94A3B8;
  border-color: #334155;
}
.dark .hero-dash-outline:hover {
  background: #1E293B;
  border-color: #475569;
  color: #E5E7EB;
}
.hero-section {
  position: relative;
  min-height: calc(100svh - var(--header-h, 5rem));
  border-bottom: 1px solid #cbd5e1;
  background: #f3f6f8;
  overflow: hidden;
}
.hero-grid {
  position: absolute;
  inset: 0;
  opacity: 0.4;
  background-image:
    linear-gradient(rgba(71, 85, 105, 0.08) 1px, transparent 1px),
    linear-gradient(90deg, rgba(71, 85, 105, 0.08) 1px, transparent 1px);
  background-size: 40px 40px;
  mask-image: linear-gradient(to bottom, #000 0%, transparent 92%);
}
.hero-layout {
  position: relative;
  z-index: 1;
  display: grid;
  width: min(100% - 2rem, 82rem);
  min-height: calc(100svh - var(--header-h, 5rem));
  margin: auto;
  align-items: center;
  gap: clamp(2rem, 5vw, 5rem);
  padding: 3.5rem 0;
}
.hero-copy {
  position: relative;
  min-width: 0;
}
.hero-label,
.hero-title,
.hero-desc,
.hero-actions {
  position: relative;
  z-index: 1;
}
.code-mark {
  position: absolute;
  pointer-events: none;
  user-select: none;
  font-family: ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
  font-weight: 700;
  letter-spacing: 0.05em;
}
.mark-tag {
  top: -1.5rem;
  left: 0.1rem;
  z-index: 5;
  font-size: 0.9rem;
  color: #0891b2;
  opacity: 0.45;
}
.mark-brace {
  top: 5%;
  right: -3rem;
  z-index: 0;
  font-size: 6rem;
  line-height: 1;
  color: #9fb4c4;
  opacity: 0.06;
}
.mark-comment {
  right: 0.5rem;
  bottom: 0.6rem;
  z-index: 5;
  font-size: 0.8rem;
  color: #5b6b7a;
  opacity: 0.4;
}
.hero-label {
  display: inline-flex;
  align-items: center;
  gap: 0.65rem;
  border: 1px solid #aebac5;
  background: rgba(248, 250, 252, 0.82);
  padding: 0.55rem 0.8rem;
  color: #0e7490;
  font-size: 0.7rem;
  font-weight: 600;
}
.status-dot {
  width: 0.45rem;
  height: 0.45rem;
  background: #06b6d4;
  box-shadow: 0 0 0 3px rgba(6, 182, 212, 0.12);
}
.hero-title {
  margin: 1.5rem 0 0;
  font-size: clamp(2.8rem, 7vw, 6.4rem);
  font-weight: 700;
  line-height: 1.08;
  letter-spacing: 0;
}
.title-line {
  display: block;
}
.title-accent {
  position: relative;
  width: fit-content;
  margin-top: 0.85rem;
  padding-block: 0.35rem;
  font-size: 1.06em;
  line-height: 1.28;
  color: #0e7490;
}
.dark .title-accent {
  color: #67e8f9;
}
.hero-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 1.8rem;
}
.hero-desc {
  margin: 0.9rem 0 0;
  max-width: 32rem;
  color: #5b6b7a;
  font-size: 1.05rem;
  font-weight: 500;
  line-height: 1.6;
}
.hero-button {
  display: inline-flex;
  min-height: 3rem;
  align-items: center;
  justify-content: center;
  gap: 0.55rem;
  border: 1px solid #9aa9b6;
  border-radius: 0.5rem;
  padding: 0.75rem 1.25rem;
  font-size: 0.875rem;
  font-weight: 600;
  transition:
    background-color 0.15s ease,
    border-color 0.15s ease,
    color 0.15s ease;
}
.hero-button:hover {
  border-color: #64748b;
  color: #0f172a;
}
.hero-button svg {
  width: 1.2rem;
  height: 1.2rem;
}
.hero-primary {
  border-color: #0e7490;
  background: #0e7490;
  color: white;
}
.hero-primary:hover {
  border-color: #155e75;
  background: #155e75;
  color: #ffffff;
}
.hero-secondary {
  background: rgba(248, 250, 252, 0.8);
  color: #334155;
}
.hero-secondary:hover {
  background: #eef2f5;
}
.terminal-stage {
  position: relative;
  isolation: isolate;
  min-width: 0;
  cursor: pointer;
  outline: none;
}
.terminal-stage::before {
  content: "";
  position: absolute;
  z-index: -1;
  inset: 0;
  border: 1px solid #52616d;
  border-radius: 0.85rem;
  transform: translate(8px, 8px);
  pointer-events: none;
}
.terminal-stage:focus-visible .terminal-frame {
  border-color: #22d3ee;
  box-shadow: 0 0 0 2px rgba(34, 211, 238, 0.2);
}
.terminal-frame {
  position: relative;
  overflow: hidden;
  border: 1px solid #8393a1;
  border-radius: 0.75rem;
  background: #111820;
  box-shadow: 0 8px 24px rgba(2, 8, 12, 0.18);
}
.terminal-frame::before {
  content: "";
  position: absolute;
  z-index: 4;
  inset: 0;
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: inherit;
  pointer-events: none;
}
.terminal-toolbar {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  min-height: 3.1rem;
  border-bottom: 1px solid #34414c;
  background: #1b252e;
  padding: 0 1rem;
}
.window-controls {
  display: flex;
  gap: 0.45rem;
}
.window-controls span {
  width: 0.55rem;
  height: 0.55rem;
  border: 1px solid #61717f;
  background: #26343f;
}
.window-controls span:nth-child(2) {
  border-color: #b78b2e;
  background: #d3a63f;
}
.file-path {
  max-width: 13rem;
  overflow: hidden;
  color: #aab8c4;
  font: 500 0.7rem/1.2 monospace;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.toolbar-icon {
  justify-self: end;
  color: #67e8f9;
}
.terminal-workspace {
  display: grid;
  min-height: 24.5rem;
  grid-template-columns: minmax(0, 68fr) minmax(11.5rem, 32fr);
}
.code-panel {
  min-width: 0;
  border-right: 1px solid #34414c;
  background: #0b1117;
}
.terminal-side {
  display: block;
  min-width: 0;
}
.panel-heading {
  display: flex;
  min-height: 2.6rem;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #2d3943;
  padding: 0 0.9rem;
  color: #8193a0;
  font: 700 0.65rem/1 monospace;
  text-transform: uppercase;
}
.panel-heading span {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}
.panel-heading svg {
  width: 1rem;
  height: 1rem;
  color: #22d3ee;
}
.editor-body {
  position: relative;
  display: grid;
  grid-template-columns: 2.4rem minmax(0, 1fr);
  height: calc(100% - 2.6rem);
  overflow: hidden;
  padding: 1.2rem 0.6rem 1rem 0;
}
.line-numbers {
  display: flex;
  flex-direction: column;
  align-items: center;
  color: #40505d;
  font: 0.75rem/1.72rem monospace;
  user-select: none;
}
.editor-body pre {
  margin: 0;
  overflow: auto hidden;
  color: #c5d1d9;
  font:
    0.78rem/1.72rem "Cascadia Code",
    Consolas,
    monospace;
  scrollbar-width: none;
}
.editor-body code {
  white-space: pre;
}
.active-line {
  position: absolute;
  z-index: 0;
  top: calc(1.2rem + 3 * 1.72rem);
  right: 0;
  left: 2.4rem;
  height: 1.72rem;
  border-left: 2px solid #22d3ee;
  background: rgba(34, 211, 238, 0.065);
}
.line-numbers,
.editor-body pre {
  position: relative;
  z-index: 1;
}
:deep(.code-directive),
:deep(.code-type) {
  color: #67e8f9;
}
:deep(.code-muted) {
  color: #71808d;
}
:deep(.code-function),
:deep(.code-number) {
  color: #f0c75e;
}
:deep(.code-object) {
  color: #9fb7c8;
}
:deep(.code-string) {
  color: #7dd3a8;
}
:deep(.code-keyword) {
  color: #f09da8;
}
.result-panel {
  display: flex;
  height: 100%;
  flex-direction: column;
  background: #131c24;
}
.judge-timeline {
  position: relative;
  display: grid;
  gap: 0.15rem;
  padding: 1rem;
}
.judge-timeline::before {
  content: "";
  position: absolute;
  top: 1.55rem;
  bottom: 1.55rem;
  left: 1.19rem;
  width: 1px;
  background: #3c4b56;
}
.judge-status {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  min-height: 2.1rem;
  padding-left: 0;
  color: #687986;
  font: 700 0.7rem/1 monospace;
}
.judge-status span {
  width: 0.4rem;
  height: 0.4rem;
  border: 1px solid #526571;
  background: #17222b;
  position: relative;
  z-index: 1;
}
.status-accepted {
  color: #8ce8ae;
}
.status-accepted svg {
  position: relative;
  z-index: 1;
  width: 0.85rem;
  height: 0.85rem;
  background: #131c24;
}
.preview-output {
  margin: auto 1rem 1rem;
  border: 1px solid #2d3b46;
  background: #0b1117;
  padding: 0.8rem;
  color: #8ce8ae;
  font: 0.72rem/1.4 monospace;
}
.language-panel {
  display: grid;
  grid-template-columns: 7.5rem minmax(0, 1fr);
  border-top: 1px solid #34414c;
  background: #101820;
}
.language-panel > .panel-heading {
  min-height: 3.65rem;
  border-right: 1px solid #2d3943;
  border-bottom: 0;
}
.language-grid {
  display: grid;
  grid-template-columns: repeat(8, minmax(0, 1fr));
  gap: 1px;
  background: #2d3943;
}
.language-button {
  display: grid;
  position: relative;
  min-width: 0;
  min-height: 3.65rem;
  place-items: center;
  border: 0;
  background: #151f27;
  filter: grayscale(1);
  opacity: 0.42;
  transition:
    background 0.15s ease,
    filter 0.15s ease,
    opacity 0.15s ease;
}
.language-button:hover,
.language-button.active {
  background: #1e2b35;
  filter: grayscale(0);
  opacity: 1;
}
.language-button.active {
  box-shadow: inset 0 -2px #22d3ee;
}
.language-button svg {
  width: 1.45rem;
  height: 1.45rem;
}
.intro {
  opacity: 0;
  transform: translateY(12px);
  animation: intro-in 0.55s cubic-bezier(0.2, 0.8, 0.2, 1) forwards;
}
.intro-label {
  animation-delay: 0.2s;
}
.intro-title-one {
  animation-delay: 0.35s;
}
.intro-title-two {
  animation-delay: 0.46s;
}
.intro-actions {
  animation-delay: 0.6s;
}
.intro-desc {
  animation-delay: 0.53s;
}
.intro-terminal {
  animation-delay: 0.7s;
}
html:not(.dark) .terminal-stage::before {
  border-color: #a7b4be;
}
html:not(.dark) .terminal-frame {
  border-color: #9eacb7;
  background: #eef3f6;
  box-shadow: 0 8px 24px rgba(51, 65, 85, 0.12);
}
html:not(.dark) .terminal-frame::before {
  border-color: rgba(71, 85, 105, 0.16);
}
html:not(.dark) .terminal-toolbar {
  border-color: #bac6cf;
  background: #e3e9ed;
}
html:not(.dark) .window-controls span {
  border-color: #9aa9b4;
  background: #c5d0d7;
}
html:not(.dark) .window-controls span:nth-child(2) {
  border-color: #b78b2e;
  background: #d3a63f;
}
html:not(.dark) .file-path {
  color: #425466;
}
html:not(.dark) .toolbar-icon,
html:not(.dark) .panel-heading svg {
  color: #087c93;
}
html:not(.dark) .code-panel {
  border-color: #bdc8d0;
  background: #f5f7f9;
}
html:not(.dark) .panel-heading {
  border-color: #c4ced5;
  color: #526371;
}
html:not(.dark) .line-numbers {
  color: #8b9aa6;
}
html:not(.dark) .editor-body pre {
  color: #1e293b;
}
html:not(.dark) .active-line {
  border-color: #0891b2;
  background: rgba(8, 145, 178, 0.08);
}
html:not(.dark) .result-panel {
  background: #eaf0f3;
}
html:not(.dark) .judge-timeline::before {
  background: #b6c2ca;
}
html:not(.dark) .judge-status {
  color: #61717d;
}
html:not(.dark) .judge-status span {
  border-color: #93a4af;
  background: #edf2f5;
}
html:not(.dark) .status-accepted {
  color: #15803d;
}
html:not(.dark) .status-accepted svg {
  background: #eaf0f3;
}
html:not(.dark) .preview-output {
  border-color: #bdc8d0;
  background: #f8fafc;
  color: #15803d;
}
html:not(.dark) .language-panel {
  border-color: #b8c4cc;
  background: #e3e9ed;
}
html:not(.dark) .language-panel > .panel-heading {
  border-color: #bdc8d0;
}
html:not(.dark) .language-grid {
  background: #c3cdd4;
}
html:not(.dark) .language-button {
  background: #f1f5f7;
}
html:not(.dark) .language-button:hover,
html:not(.dark) .language-button.active {
  background: #e5f5f7;
}
.dark .home-shell {
  background: #070c11;
  color: #e6edf2;
}
.dark .hero-section {
  border-color: #26343e;
  background: #080e13;
}
.dark .hero-grid {
  opacity: 0.3;
  background-image:
    linear-gradient(rgba(148, 163, 184, 0.07) 1px, transparent 1px),
    linear-gradient(90deg, rgba(148, 163, 184, 0.07) 1px, transparent 1px);
}
.dark .hero-label {
  border-color: #344550;
  background: rgba(11, 18, 24, 0.8);
  color: #67e8f9;
}
.dark .hero-secondary {
  border-color: #45545f;
  background: rgba(15, 23, 31, 0.8);
  color: #d2dce3;
}
.dark .hero-desc {
  color: #aab6c2;
}
.dark .mark-tag {
  color: #22d3ee;
}
.dark .mark-brace {
  color: #4b6275;
}
.dark .mark-comment {
  color: #7c8a97;
}
@media (min-width: 1024px) {
  .hero-layout {
    grid-template-columns: minmax(22rem, 0.82fr) minmax(31rem, 1.18fr);
  }
}
@media (max-width: 1023px) {
  .hero-layout {
    align-content: center;
    padding-block: 4.5rem;
  }
  .terminal-stage {
    width: min(100%, 44rem);
  }
}
@media (max-width: 640px) {
  .hero-layout {
    width: min(100% - 1.25rem, 82rem);
    gap: 2.75rem;
    padding-block: 3rem;
  }
  .hero-title {
    font-size: clamp(2.55rem, 13.5vw, 4rem);
  }
  .hero-actions {
    display: grid;
    grid-template-columns: 1fr;
  }
  .hero-button {
    width: 100%;
  }
  .terminal-workspace {
    min-height: 0;
    grid-template-columns: 1fr;
  }
  .code-panel {
    min-height: 18rem;
    border-right: 0;
    border-bottom: 1px solid #34414c;
  }
  .terminal-side {
    display: block;
  }
  .editor-body pre {
    font-size: 0.69rem;
    line-height: 1.55rem;
  }
  .line-numbers {
    line-height: 1.55rem;
  }
  .active-line {
    top: calc(1.2rem + 3 * 1.55rem);
    height: 1.55rem;
  }
  .result-panel {
    min-height: 13.5rem;
  }
  .file-path {
    max-width: 10rem;
  }
  .terminal-frame {
    box-shadow: 8px 10px 0 rgba(15, 23, 42, 0.1);
  }
  .terminal-stage::before {
    transform: translate(6px, 6px);
  }
  .language-panel {
    grid-template-columns: 1fr;
  }
  .language-panel > .panel-heading {
    min-height: 2.35rem;
    border-right: 0;
    border-bottom: 1px solid #2d3943;
  }
  .language-button {
    min-height: 2.8rem;
  }
  .language-button svg {
    width: 1.15rem;
    height: 1.15rem;
  }
}
@media (prefers-reduced-motion: reduce) {
  .intro {
    animation: none !important;
    opacity: 1;
    transform: none;
  }
  .terminal-frame,
  .hero-button,
  .language-button {
    transition-duration: 0.01ms !important;
  }
}
@keyframes intro-in {
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>

<style>
html:not(.dark) .home-shell .editor-body code {
  color: #0f172a;
}

html:not(.dark) .home-shell .code-directive,
html:not(.dark) .home-shell .code-type {
  color: #00677f;
  font-weight: 600;
}

html:not(.dark) .home-shell .code-muted {
  color: #475569;
}

html:not(.dark) .home-shell .code-function,
html:not(.dark) .home-shell .code-number {
  color: #854d0e;
  font-weight: 600;
}

html:not(.dark) .home-shell .code-object {
  color: #075985;
}

html:not(.dark) .home-shell .code-string {
  color: #166534;
}

html:not(.dark) .home-shell .code-keyword {
  color: #9f1239;
  font-weight: 600;
}
</style>
