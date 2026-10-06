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
  { name: "JavaScript", value: "javascript", icon: "vscode-icons:file-type-js-official" },
  { name: "Python", value: "python", icon: "vscode-icons:file-type-python" },
  { name: "Java", value: "java", icon: "vscode-icons:file-type-java" },
  { name: "C++", value: "cpp", icon: "vscode-icons:file-type-cpp" },
  { name: "Go", value: "go", icon: "vscode-icons:file-type-go" },
  { name: "Rust", value: "rust", icon: "vscode-icons:file-type-rust" },
]);

const codeSamples: Record<string, string> = {
  cpp: `<span class="tok-directive">#include</span> <span class="tok-muted">&lt;iostream&gt;</span>\n\n<span class="tok-type">int</span> <span class="tok-function">main</span>() {\n  <span class="tok-object">std::cout</span> <span class="tok-muted">&lt;&lt;</span> <span class="tok-string">"Hello, Let Coding!"</span> <span class="tok-muted">&lt;&lt;</span> <span class="tok-string">'\\n'</span>;\n  <span class="tok-keyword">return</span> <span class="tok-number">0</span>;\n}`,
  python: `<span class="tok-keyword">print</span>(<span class="tok-string">"Hello, Let Coding!"</span>)`,
  javascript: `<span class="tok-object">console</span>.<span class="tok-function">log</span>(<span class="tok-string">"Hello, Let Coding!"</span>);`,
  java: `<span class="tok-keyword">public</span> <span class="tok-type">class</span> <span class="tok-function">Main</span> {\n  <span class="tok-keyword">public</span> <span class="tok-type">static void</span> <span class="tok-function">main</span>(<span class="tok-object">String</span>[] args) {\n    <span class="tok-object">System.out</span>.<span class="tok-function">println</span>(<span class="tok-string">"Hello, Let Coding!"</span>);\n  }\n}`,
  go: `<span class="tok-keyword">package</span> <span class="tok-function">main</span>\n<span class="tok-keyword">import</span> <span class="tok-string">"fmt"</span>\n\n<span class="tok-type">func</span> <span class="tok-function">main</span>() {\n  <span class="tok-object">fmt</span>.<span class="tok-function">Println</span>(<span class="tok-string">"Hello, Let Coding!"</span>)\n}`,
  rust: `<span class="tok-type">fn</span> <span class="tok-function">main</span>() {\n  <span class="tok-object">println!</span>(<span class="tok-string">"Hello, Let Coding!"</span>);\n}`,
};

const extMap: Record<string, string> = {
  cpp: "cpp",
  python: "py",
  javascript: "js",
  java: "java",
  go: "go",
  rust: "rs",
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
    {
      key: "easy",
      label: "简单",
      value: easy,
      pct: Math.round((easy / total) * 100),
      badgeClass: "ui-diff-easy",
      barColor: "var(--color-signal)",
    },
    {
      key: "mid",
      label: "中等",
      value: mid,
      pct: Math.round((mid / total) * 100),
      badgeClass: "ui-diff-mid",
      barColor: "var(--color-warning)",
    },
    {
      key: "hard",
      label: "困难",
      value: hard,
      pct: Math.round((hard / total) * 100),
      badgeClass: "ui-diff-hard",
      barColor: "var(--color-danger)",
    },
  ];
});

const metrics = computed(() => [
  { key: "solved", label: "已解决", value: solvedCount.value, icon: "material-symbols:check-circle-rounded" },
  { key: "submissions", label: "提交总数", value: submissionTotal.value, icon: "material-symbols:history-rounded" },
  { key: "favorites", label: "收藏", value: favoriteCount.value, icon: "material-symbols:star-rounded" },
  { key: "problems", label: "题库题量", value: totalProblems.value, icon: "material-symbols:library-books-rounded" },
]);

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
  <div class="home">
    <!-- ============ Hero ============ -->
    <section class="hero">
      <div class="app-container hero-layout">
        <div class="hero-copy">
          <h1 class="hero-title">写代码，更加顺手</h1>

          <p class="hero-desc">
            在线编写、运行和提交代码，支持多语言判题与实时反馈。
          </p>

          <div class="hero-actions">
            <button
              type="button"
              class="ui-btn ui-btn-primary ui-btn-lg hero-cta"
              @click="router.push('/playground')"
            >
              <Icon icon="material-symbols:play-arrow-rounded" class="h-5 w-5" aria-hidden="true" />
              <span>进入在线编辑器</span>
            </button>
            <button
              type="button"
              class="ui-btn ui-btn-secondary ui-btn-lg hero-cta"
              @click="router.push('/learn')"
            >
              <Icon icon="material-symbols:school-rounded" class="h-5 w-5" aria-hidden="true" />
              <span>查看学习资源</span>
            </button>
          </div>
        </div>

        <div
          ref="terminalRef"
          class="terminal"
          role="link"
          tabindex="0"
          aria-label="进入在线编辑器"
          @click="handleTerminalClick"
          @keydown="handleTerminalKeydown"
        >
          <div class="terminal-frame">
            <div class="terminal-toolbar">
              <div class="terminal-dots" aria-hidden="true">
                <span></span><span></span><span></span>
              </div>
              <div class="terminal-path">playground/main.{{ currentFileExt }}</div>
              <Icon
                icon="material-symbols:terminal-rounded"
                class="terminal-toolbar-icon"
                aria-hidden="true"
              />
            </div>

            <div class="terminal-workspace">
              <section class="terminal-code">
                <h2 class="panel-heading">
                  <Icon icon="material-symbols:code-rounded" aria-hidden="true" />
                  Sample Code
                </h2>
                <div class="editor-body">
                  <div class="editor-active-line" aria-hidden="true"></div>
                  <div class="editor-gutter" aria-hidden="true">
                    <span v-for="line in 7" :key="line">{{ line }}</span>
                  </div>
                  <pre><code v-html="currentCode"></code></pre>
                </div>
              </section>

              <section class="terminal-result">
                <h2 class="panel-heading">运行结果</h2>
                <ol class="judge-timeline">
                  <li class="judge-step is-compiling">
                    <Icon icon="material-symbols:build-rounded" aria-hidden="true" />
                    <span>Compiling</span>
                  </li>
                  <li class="judge-step is-running">
                    <Icon icon="material-symbols:play-arrow-rounded" aria-hidden="true" />
                    <span>Running</span>
                  </li>
                  <li class="judge-step is-accepted">
                    <Icon icon="material-symbols:check-circle-rounded" aria-hidden="true" />
                    <span>Accepted</span>
                  </li>
                </ol>
                <p class="judge-output">
                  <span class="judge-output-label">stdout</span>
                  <span class="judge-output-value">Hello, Let Coding!</span>
                </p>
              </section>
            </div>

            <section class="language-panel">
              <h2 class="panel-heading">支持语言</h2>
              <div class="language-segment">
                <div
                  class="ui-segmented ui-segmented-fill"
                  role="group"
                  aria-label="示例代码语言"
                >
                  <button
                    v-for="language in languages"
                    :key="language.value"
                    type="button"
                    class="ui-segmented-item language-tab"
                    :class="{ 'is-active': currentLanguage === language.value }"
                    :aria-label="language.name"
                    :aria-pressed="currentLanguage === language.value"
                    @click.stop="selectLanguage(language)"
                  >
                    <Icon :icon="language.icon" aria-hidden="true" />
                  </button>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </section>

    <!-- ============ Dashboard ============ -->
    <section class="dashboard" v-if="authStore.isAuthenticated">
      <div class="app-container">
        <div class="ui-panel dash-panel">
          <!-- 行动条 -->
          <div class="dash-action">
            <div class="dash-action-identity">
              <Icon
                :icon="
                  authStore.isAuthenticated
                    ? 'material-symbols:account-circle-rounded'
                    : 'material-symbols:login-rounded'
                "
                class="dash-action-icon"
                aria-hidden="true"
              />
              <div class="dash-action-text">
                <h2 class="ui-section-title">
                  {{
                    authStore.isAuthenticated
                      ? authStore.displayName || "同学"
                      : "登录后开始刷题"
                  }}
                </h2>
                <p class="ui-section-sub">
                  {{
                    authStore.isAuthenticated
                      ? "查看最近提交与学习进度"
                      : "同步提交记录、收藏与学习进度"
                  }}
                </p>
              </div>
            </div>
            <div class="dash-action-buttons">
              <router-link to="/problems" class="ui-btn ui-btn-primary ui-btn-sm">
                <Icon icon="material-symbols:play-arrow-rounded" class="h-4 w-4" aria-hidden="true" />
                开始刷题
              </router-link>
              <router-link to="/playground" class="ui-btn ui-btn-secondary ui-btn-sm">
                <Icon icon="material-symbols:code-rounded" class="h-4 w-4" aria-hidden="true" />
                打开编辑器
              </router-link>
              <router-link to="/contests" class="ui-btn ui-btn-ghost ui-btn-sm">
                <Icon icon="material-symbols:trophy-rounded" class="h-4 w-4" aria-hidden="true" />
                查看比赛
              </router-link>
            </div>
          </div>

          <hr class="ui-divider" />

          <!-- 指标横排 -->
          <dl class="dash-metrics">
            <div v-for="metric in metrics" :key="metric.key" class="dash-metric">
              <dt class="dash-metric-label">
                <Icon :icon="metric.icon" class="h-4 w-4" aria-hidden="true" />
                {{ metric.label }}
              </dt>
              <dd class="dash-metric-value">
                <span v-if="dashboardLoading" class="ui-skeleton dash-metric-skeleton"></span>
                <template v-else>{{ metric.value }}</template>
              </dd>
            </div>
          </dl>

          <hr class="ui-divider" />

          <!-- 两列活动 -->
          <div class="dash-lists">
            <section class="dash-list">
              <header class="dash-list-head">
                <h3 class="ui-section-title">继续学习</h3>
                <router-link to="/problems" class="ui-link text-xs">全部题目</router-link>
              </header>
              <div v-if="dashboardLoading" class="dash-list-skeleton">
                <span v-for="i in 5" :key="i" class="ui-skeleton h-11"></span>
              </div>
              <ul v-else-if="recentProblems.length" class="dash-rows">
                <li v-for="p in recentProblems" :key="p.id">
                  <router-link :to="`/problems/${p.id}`" class="dash-row">
                    <span class="dash-row-title">{{ p.title }}</span>
                    <span
                      v-if="p.difficulty"
                      class="ui-diff"
                      :class="
                        p.difficulty === '简单'
                          ? 'ui-diff-easy'
                          : p.difficulty === '中等'
                            ? 'ui-diff-mid'
                            : 'ui-diff-hard'
                      "
                      >{{ p.difficulty }}</span
                    >
                    <span class="dash-row-meta">
                      通过率 {{ formatRate(p.accepted_count, p.submission_count) }}
                    </span>
                  </router-link>
                </li>
              </ul>
              <p v-else class="ui-empty">暂无题目</p>
            </section>

            <section class="dash-list">
              <header class="dash-list-head">
                <h3 class="ui-section-title">最近活动</h3>
                <router-link to="/submissions" class="ui-link text-xs">全部记录</router-link>
              </header>
              <div v-if="dashboardLoading" class="dash-list-skeleton">
                <span v-for="i in 5" :key="i" class="ui-skeleton h-11"></span>
              </div>
              <ul v-else-if="recentSubmissions.length" class="dash-rows">
                <li v-for="s in recentSubmissions" :key="s.id">
                  <button type="button" class="dash-row" @click="goProblem(s.problem_id)">
                    <span class="ui-badge" :class="statusClass(s.status)">{{
                      statusLabel(s.status)
                    }}</span>
                    <span class="dash-row-title">{{ s.problem_title }}</span>
                    <span class="dash-row-meta">{{ formatDateShort(s.created_at) }}</span>
                  </button>
                </li>
              </ul>
              <p v-else class="ui-empty">暂无提交记录</p>
            </section>
          </div>

          <hr class="ui-divider" />

          <!-- 难度分布 -->
          <section class="dash-difficulty">
            <h3 class="ui-section-title">题库难度分布</h3>
            <ul class="difficulty-list">
              <li v-for="item in difficultyRows" :key="item.key" class="difficulty-row">
                <span class="ui-diff" :class="item.badgeClass">{{ item.label }}</span>
                <div
                  class="difficulty-bar"
                  role="img"
                  :aria-label="`${item.label} ${item.value} 题，占比 ${item.pct}%`"
                >
                  <span
                    class="difficulty-bar-fill"
                    :style="{ width: item.pct + '%', background: item.barColor }"
                  ></span>
                </div>
                <span class="difficulty-value">{{ item.value }} 题</span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
@reference "tailwindcss";

.home {
  background: var(--color-background);
  color: var(--color-foreground);
}

/* ============================================================
   Hero
   ============================================================ */
.hero {
  display: flex;
  align-items: center;
  min-height: min(calc(100svh - var(--header-h, 4rem)), 52rem);
  padding-block: clamp(2.5rem, 6vw, 5rem);
}

.hero-layout {
  display: grid;
  align-items: center;
  gap: clamp(2rem, 5vw, 4.5rem);
}

.hero-copy {
  min-width: 0;
}

.hero-eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  font-size: 0.8125rem;
  font-weight: 500;
  letter-spacing: 0.01em;
  color: var(--color-muted-foreground);
}
.hero-dot {
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 999px;
  background: var(--color-signal);
}

.hero-title {
  margin: 1.25rem 0 0;
  font-size: clamp(2.25rem, 5.2vw, 3.75rem);
  font-weight: 700;
  line-height: 1.12;
  letter-spacing: -0.022em;
  color: var(--color-foreground);
  text-wrap: balance;
}

.hero-desc {
  margin: 1.125rem 0 0;
  max-width: 34rem;
  font-size: 1.0625rem;
  line-height: 1.6;
  color: var(--color-muted-foreground);
}

.hero-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 2rem;
}
.hero-cta {
  @apply min-w-[10.5rem];
}

/* ============================================================
   终端：首页唯一重点视觉（跟随主题的代码表面）
   ============================================================ */
.terminal {
  min-width: 0;
  cursor: pointer;
  outline: none;
}
.terminal:focus-visible .terminal-frame {
  outline: 2px solid var(--color-ring);
  outline-offset: 3px;
}

.terminal-frame {
  overflow: hidden;
  border: 1px solid var(--color-term-line);
  border-radius: var(--radius-tool);
  background: var(--color-term-bg);
  box-shadow: var(--shadow-tool);
}

.terminal-toolbar {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  min-height: 2.75rem;
  border-bottom: 1px solid var(--color-term-line);
  background: var(--color-term-surface);
  padding: 0 1rem;
}
.terminal-dots {
  display: flex;
  gap: 0.4rem;
}
.terminal-dots span {
  width: 0.625rem;
  height: 0.625rem;
  border-radius: 999px;
  background: var(--color-term-dot-3);
}
.terminal-dots span:first-child {
  background: var(--color-term-dot-1);
}
.terminal-dots span:nth-child(2) {
  background: var(--color-term-dot-2);
}
.terminal-path {
  max-width: 14rem;
  overflow: hidden;
  font-family: var(--font-mono);
  font-size: 0.6875rem;
  color: var(--color-term-path);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.terminal-toolbar-icon {
  justify-self: end;
  width: 1.05rem;
  height: 1.05rem;
  color: var(--color-term-accent);
}

.terminal-workspace {
  display: grid;
  grid-template-columns: minmax(0, 68fr) minmax(11rem, 32fr);
  min-height: 21rem;
}

.panel-heading {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  min-height: 2.4rem;
  margin: 0;
  border-bottom: 1px solid var(--color-term-line-soft);
  padding: 0 0.9rem;
  font-family: var(--font-mono);
  font-size: 0.6875rem;
  font-weight: 500;
  letter-spacing: 0.02em;
  color: var(--color-term-muted);
}
.panel-heading :deep(svg) {
  width: 0.95rem;
  height: 0.95rem;
  color: var(--color-term-accent);
}

.terminal-code {
  min-width: 0;
  border-right: 1px solid var(--color-term-line);
  background: var(--color-term-bg);
}

.editor-body {
  position: relative;
  display: grid;
  grid-template-columns: 2.5rem minmax(0, 1fr);
  height: calc(100% - 2.4rem);
  overflow: hidden;
  padding: 1rem 0.75rem 1rem 0;
}
.editor-gutter {
  display: flex;
  flex-direction: column;
  align-items: center;
  font-family: var(--font-mono);
  font-size: 0.75rem;
  line-height: 1.7rem;
  color: var(--color-term-gutter);
  user-select: none;
}
.editor-body pre {
  margin: 0;
  overflow-x: auto;
  color: var(--color-term-text);
  font-family: var(--font-mono);
  font-size: 0.78125rem;
  line-height: 1.7rem;
}
.editor-body code {
  white-space: pre;
}
.editor-active-line {
  position: absolute;
  z-index: 0;
  top: calc(1rem + 3 * 1.7rem);
  right: 0;
  left: 2.5rem;
  height: 1.7rem;
  border-left: 2px solid var(--color-term-accent);
  background: var(--color-term-active-line);
}
.editor-gutter,
.editor-body pre {
  position: relative;
  z-index: 1;
}

/* 代码语义色：浅色/深色各自定义，保证在对应表面上的对比度 */
:deep(.tok-directive),
:deep(.tok-type) {
  color: var(--color-term-code-directive);
}
:deep(.tok-muted) {
  color: var(--color-term-code-muted);
}
:deep(.tok-function),
:deep(.tok-number) {
  color: var(--color-term-code-function);
}
:deep(.tok-object) {
  color: var(--color-term-code-object);
}
:deep(.tok-string) {
  color: var(--color-term-code-string);
}
:deep(.tok-keyword) {
  color: var(--color-term-code-keyword);
}

.terminal-result {
  display: flex;
  min-width: 0;
  flex-direction: column;
  background: var(--color-term-surface);
}

.judge-timeline {
  display: grid;
  gap: 0.15rem;
  margin: 0;
  padding: 0.9rem;
  list-style: none;
}
.judge-step {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-height: 2rem;
  font-family: var(--font-mono);
  font-size: 0.6875rem;
  font-weight: 500;
}
.judge-step :deep(svg) {
  width: 0.95rem;
  height: 0.95rem;
  flex-shrink: 0;
}
/* 状态同时使用图标 + 文字 + 颜色，不依赖单一颜色差异 */
.is-compiling {
  color: var(--color-term-warn);
}
.is-running {
  color: var(--color-term-accent);
}
.is-accepted {
  color: var(--color-term-ok);
}

.judge-output {
  display: grid;
  gap: 0.35rem;
  margin: auto 0.9rem 0.9rem;
  border: 1px solid var(--color-term-line);
  border-radius: var(--radius-card);
  background: var(--color-term-bg);
  padding: 0.7rem 0.8rem;
}
.judge-output-label {
  font-family: var(--font-mono);
  font-size: 0.625rem;
  letter-spacing: 0.04em;
  color: var(--color-term-muted);
}
.judge-output-value {
  font-family: var(--font-mono);
  font-size: 0.75rem;
  color: var(--color-term-code-string);
}

.language-panel {
  display: grid;
  grid-template-columns: 7.5rem minmax(0, 1fr);
  border-top: 1px solid var(--color-term-line);
  background: var(--color-term-surface);
}
.language-panel > .panel-heading {
  min-height: 3.4rem;
  border-right: 1px solid var(--color-term-line-soft);
  border-bottom: 0;
  padding: 0 1rem;
}
/* 语言切换复用全局 .ui-segmented（iOS 分段控件），此处只补图标专用的尺寸与未选中态 */
.language-segment {
  display: flex;
  align-items: center;
  padding: 0.375rem 0.9rem;
}
.language-tab {
  padding-inline: 0.25rem;
  opacity: 0.45;
  transition: opacity 0.18s ease;
}
.language-tab:hover {
  opacity: 0.75;
}
.language-tab.is-active,
.language-tab.is-active:hover {
  opacity: 1;
}
.language-tab :deep(svg) {
  width: 1.25rem;
  height: 1.25rem;
}

/* ============================================================
   Dashboard：平面分组 + 分隔线，不做卡片嵌套
   ============================================================ */
.dashboard {
  padding-block: clamp(2rem, 4vw, 3rem);
}

.dash-panel {
  overflow: hidden;
}

.dash-action {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 1.25rem;
}
.dash-action-identity {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 0.85rem;
}
.dash-action-icon {
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  color: var(--color-accent);
}
.dash-action-text {
  min-width: 0;
}
.dash-action-text .ui-section-title,
.dash-action-text .ui-section-sub {
  @apply truncate;
}
.dash-action-buttons {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.dash-metrics {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  margin: 0;
}
.dash-metric {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 0.35rem;
  padding: 1.1rem 1.25rem;
  border-left: 1px solid var(--color-border);
}
.dash-metric:first-child,
.dash-metric:nth-child(2n + 1) {
  border-left: 0;
}
.dash-metric:nth-child(n + 3) {
  border-top: 1px solid var(--color-border);
}
.dash-metric-label {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--color-muted-foreground);
}
.dash-metric-value {
  margin: 0;
  font-size: 1.625rem;
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.02em;
  color: var(--color-foreground);
}
.dash-metric-skeleton {
  display: inline-block;
  width: 3rem;
  height: 1.5rem;
}

.dash-lists {
  display: grid;
}
.dash-list {
  min-width: 0;
  padding: 1.25rem;
}
.dash-list + .dash-list {
  border-top: 1px solid var(--color-border);
}
.dash-list-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 0.75rem;
}
/* 次级文字链接补足 44px 触控区域，内边距由等量负外边距抵消，不产生位移 */
.dash-list-head .ui-link {
  display: inline-flex;
  min-height: 44px;
  align-items: center;
  padding-inline: 0.5rem;
  margin: -0.875rem -0.5rem;
}
.dash-list-skeleton {
  display: grid;
  gap: 0.375rem;
}

/* 面板本身已提供分组边界，内部空状态不再叠加一层描边 */
.dash-list .ui-empty {
  border: 0;
  background: transparent;
  padding-block: 2rem;
}

.dash-rows {
  margin: 0;
  padding: 0;
  list-style: none;
}
.dash-rows > li + li {
  border-top: 1px solid var(--color-border);
}
.dash-row {
  display: flex;
  width: 100%;
  min-height: 44px;
  align-items: center;
  gap: 0.65rem;
  border-radius: 6px;
  padding: 0.35rem 0.5rem;
  text-align: left;
  transition: background-color 0.15s ease;
}
.dash-row:hover {
  background: var(--color-surface-muted);
}
.dash-row-title {
  min-width: 0;
  flex: 1;
  overflow: hidden;
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--color-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.dash-row-meta {
  flex-shrink: 0;
  font-size: 0.75rem;
  font-variant-numeric: tabular-nums;
  color: var(--color-muted-foreground);
}

.dash-difficulty {
  padding: 1.25rem;
}
.difficulty-list {
  display: grid;
  gap: 0.85rem;
  margin: 0.85rem 0 0;
  padding: 0;
  list-style: none;
}
.difficulty-row {
  display: grid;
  grid-template-columns: 3.5rem minmax(0, 1fr) 4rem;
  align-items: center;
  gap: 0.85rem;
}
.difficulty-bar {
  height: 6px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--color-muted);
}
.difficulty-bar-fill {
  display: block;
  height: 100%;
  border-radius: 999px;
}
.difficulty-value {
  font-size: 0.8125rem;
  font-variant-numeric: tabular-nums;
  text-align: right;
  color: var(--color-muted-foreground);
}

/* ============================================================
   响应式
   ============================================================ */
@media (min-width: 640px) {
  .dash-metrics {
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }
  .dash-metric:nth-child(2n + 1) {
    border-left: 1px solid var(--color-border);
  }
  .dash-metric:first-child {
    border-left: 0;
  }
  .dash-metric:nth-child(n + 3) {
    border-top: 0;
  }
}

/* Hero 双栏需要终端有足够宽度，窄于此宽度改为上下堆叠，避免代码被截断 */
@media (min-width: 1120px) {
  .hero-layout {
    grid-template-columns: minmax(0, 0.85fr) minmax(30rem, 1.15fr);
  }
}

@media (min-width: 1024px) {
  .dash-lists {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .dash-list + .dash-list {
    border-top: 0;
    border-left: 1px solid var(--color-border);
  }
}

@media (max-width: 1119px) {
  .terminal {
    width: min(100%, 44rem);
    justify-self: center;
  }
}

@media (max-width: 639px) {
  .hero {
    padding-block: 2.5rem;
  }
  .hero-actions {
    display: grid;
    grid-template-columns: 1fr;
  }
  .hero-cta {
    width: 100%;
  }
  .terminal-workspace {
    grid-template-columns: 1fr;
    min-height: 0;
  }
  .terminal-code {
    border-right: 0;
    border-bottom: 1px solid var(--color-term-line);
  }
  .editor-body {
    min-height: 15rem;
  }
  .editor-body pre,
  .editor-gutter {
    font-size: 0.6875rem;
    line-height: 1.55rem;
  }
  .editor-active-line {
    top: calc(1rem + 3 * 1.55rem);
    height: 1.55rem;
  }
  .terminal-result {
    min-height: 12rem;
  }
  .terminal-path {
    max-width: 8.5rem;
  }
  .language-panel {
    grid-template-columns: 1fr;
  }
  .language-panel > .panel-heading {
    min-height: 2.25rem;
    border-right: 0;
    border-bottom: 1px solid var(--color-term-line-soft);
  }
  .language-segment {
    padding: 0.375rem 0.6rem;
  }
  .language-tab :deep(svg) {
    width: 1.1rem;
    height: 1.1rem;
  }
  .dash-action {
    padding: 1rem;
  }
  .dash-action-buttons {
    width: 100%;
  }
  .dash-list,
  .dash-difficulty {
    padding: 1rem;
  }
  .difficulty-row {
    grid-template-columns: 3.25rem minmax(0, 1fr) 3.25rem;
    gap: 0.65rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .language-tab,
  .dash-row {
    transition-duration: 0.01ms !important;
  }
}
</style>
