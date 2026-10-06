<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Icon } from '@iconify/vue';
import { useMessage } from 'naive-ui';
import { useProblemStats } from '../composables/useProblemStats';
import { useAuthStore } from '../stores/auth';
import { apiRequest, listFavorites, addFavorite, removeFavorite } from '../services/api';

const route = useRoute();

interface Problem {
  id: number;
  sourceNumber?: number;
  category: string;
  categoryLabel?: string;
  title: string;
  difficulty: '简单' | '中等' | '困难';
  tags: string[];
  interactive?: boolean;
  judgeable?: boolean;
}

interface ProblemListResponse {
  data: Problem[];
  total: number;
}

const router = useRouter();
const message = useMessage();
const searchQuery = ref('');
// 输入防抖：避免每次按键都对整表做模糊匹配
const activeSearchQuery = ref('');
let searchDebounceTimer: ReturnType<typeof setTimeout> | null = null;
watch(searchQuery, (value) => {
  if (searchDebounceTimer) clearTimeout(searchDebounceTimer);
  searchDebounceTimer = setTimeout(() => {
    activeSearchQuery.value = value;
  }, 150);
});
onUnmounted(() => {
  if (searchDebounceTimer) clearTimeout(searchDebounceTimer);
});
const difficultyFilter = ref<string>('');
const categoryFilter = ref('');
const statusFilter = ref<'' | 'solved' | 'unsolved' | 'attempted' | 'favorite'>('');
const sortMode = ref<'latest' | 'number'>('latest');
const isLoading = ref(true);
const loadError = ref('');
const { getStats } = useProblemStats();
const authStore = useAuthStore();

const problems = shallowRef<Problem[]>([]);
const favoriteIds = ref<Set<number>>(new Set());

// 统一处理空格和常见分隔符，让 "binary search"、"binary-search" 等写法都能命中。
const normalizeSearchText = (value: string) =>
  value.toLocaleLowerCase().replace(/[\s\-_./\\()[\]{}:：,，。]+/g, '');

const fuzzyMatch = (value: string, query: string) => {
  const text = normalizeSearchText(value);
  const normalizedQuery = normalizeSearchText(query);
  if (!normalizedQuery) return true;
  if (text.includes(normalizedQuery)) return true;

  let queryIndex = 0;
  for (const character of text) {
    if (character === normalizedQuery[queryIndex]) queryIndex += 1;
    if (queryIndex === normalizedQuery.length) return true;
  }
  return false;
};

const loadProblems = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const response = await apiRequest<ProblemListResponse>('/problems', { skipAuth: true });
    problems.value = response.data;
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : '题目加载失败，请稍后重试。';
  } finally {
    isLoading.value = false;
  }
};

const loadFavorites = async () => {
  if (!authStore.isAuthenticated) {
    favoriteIds.value = new Set();
    return;
  }
  try {
    const res = await listFavorites();
    favoriteIds.value = new Set(res.data.map((item) => item.problem_id));
  } catch {
    favoriteIds.value = new Set();
  }
};

const categoryLabelMap: Record<string, string> = {
  'general': '练习',
  'c-language': 'C语言专栏',
};
const categoryDisplayName = (key: string) => categoryLabelMap[key] || key;

interface CategoryOption {
  key: string;
  label: string;
}
const categories = computed<CategoryOption[]>(() => {
  const seen = new Map<string, string>();
  for (const p of problems.value) {
    if (!p.category) continue;
    if (!seen.has(p.category)) {
      seen.set(p.category, p.categoryLabel || categoryDisplayName(p.category));
    }
  }
  return Array.from(seen, ([key, label]) => ({ key, label }))
    .filter(({ label }) => label.trim() !== '1');
});

const filteredProblems = computed(() => {
  const q = activeSearchQuery.value.trim();
  return problems.value
    .filter((p) => {
      if (categoryFilter.value && p.category !== categoryFilter.value) return false;
      if (difficultyFilter.value && p.difficulty !== difficultyFilter.value) return false;
      const stat = getStats(p.id);
      if (statusFilter.value === 'solved' && !(authStore.isAuthenticated && stat.accepted > 0)) return false;
      if (statusFilter.value === 'unsolved' && authStore.isAuthenticated && stat.accepted > 0) return false;
      if (statusFilter.value === 'attempted' && !(authStore.isAuthenticated && stat.attempted)) return false;
      if (statusFilter.value === 'favorite' && !favoriteIds.value.has(p.id)) return false;
      if (q) {
        return (
          fuzzyMatch(p.title, q) ||
          p.tags.some((t) => fuzzyMatch(t, q)) ||
          fuzzyMatch(p.categoryLabel || p.category, q) ||
          fuzzyMatch(String(p.sourceNumber || p.id), q)
        );
      }
      return true;
    })
    .map((p) => {
      const stat = getStats(p.id);
      return {
        ...p,
        stat,
        isAccepted: authStore.isAuthenticated && stat.accepted > 0,
        isAttempted: authStore.isAuthenticated && stat.attempted,
        acceptRate: stat.submissions > 0 ? Math.round((stat.accepted / stat.submissions) * 100) : null,
      };
    })
    .sort((a, b) => {
      const aNumber = a.sourceNumber ?? a.id;
      const bNumber = b.sourceNumber ?? b.id;
      return sortMode.value === 'latest' ? bNumber - aNumber : aNumber - bNumber;
    });
});

// 只有当结果中确实存在统计数据时才为统计列预留宽度，
// 否则难度标签会因为一列空文本而漂在行中间。
const hasAnyStats = computed(() =>
  filteredProblems.value.some((p) => p.acceptRate != null || p.stat.submissions > 0)
);

const openProblem = (id: number) => {
  router.push(`/problems/${id}`);
};

const isFavorited = (id: number) => favoriteIds.value.has(id);

const openRandomProblem = () => {
  const candidates = filteredProblems.value;
  if (!candidates.length) {
    message.info('当前筛选条件下没有可打开的题目');
    return;
  }
  const selectedProblem = candidates[Math.floor(Math.random() * candidates.length)];
  if (selectedProblem) openProblem(selectedProblem.id);
};

const goLogin = () => {
  authStore.startOAuthLogin('iOSClub', router.currentRoute.value.fullPath, true);
};

const toggleFavorite = async (problem: Problem, event: MouseEvent) => {
  event.stopPropagation();
  if (!authStore.isAuthenticated) {
    message.warning('请先登录后再收藏题目');
    goLogin();
    return;
  }
  const favorited = favoriteIds.value.has(problem.id);
  const next = new Set(favoriteIds.value);
  try {
    const res = favorited ? await removeFavorite(problem.id) : await addFavorite(problem.id);
    if (res.favorited) next.add(problem.id);
    else next.delete(problem.id);
    favoriteIds.value = next;
    message.success(res.favorited ? '已加入收藏题目' : '已取消收藏');
  } catch (error) {
    message.error(error instanceof Error ? error.message : '操作失败，请稍后重试');
  }
};

// 状态不只靠颜色传达：图标形状不同，同时提供文字供辅助技术读取
const rowStatusText = (p: { isAccepted: boolean; isAttempted: boolean }) =>
  p.isAccepted ? '已解决' : p.isAttempted ? '尝试过' : '未解决';

const difficultyClass = (d: string) =>
  d === '简单'
    ? 'ui-diff ui-diff-easy'
    : d === '中等'
      ? 'ui-diff ui-diff-mid'
      : 'ui-diff ui-diff-hard';

const resetFilters = () => {
  searchQuery.value = '';
  difficultyFilter.value = '';
  categoryFilter.value = '';
  statusFilter.value = '';
};

onMounted(() => {
  const q = route.query.q;
  const tag = route.query.tag;
  if (typeof q === 'string' && q.trim()) {
    searchQuery.value = q.trim();
  } else if (typeof tag === 'string' && tag.trim()) {
    searchQuery.value = tag.trim();
  }
  loadProblems();
  loadFavorites();
});
</script>

<template>
  <div class="problems-page bg-[var(--color-background)]">
    <div class="app-container py-6">
      <div class="flex items-start gap-4 lg:gap-6">
        <!-- 左侧筛选 -->
        <aside data-testid="problem-filter-card" class="problem-filter-card hidden w-60 shrink-0 lg:block">
          <div class="space-y-6">
            <section>
              <div class="ui-section-title mb-2 text-sm">状态</div>
              <div class="flex flex-col gap-1">
                <button
                  v-for="opt in [
                    { v: '', label: '全部题目' },
                    { v: 'solved', label: '已解决' },
                    { v: 'attempted', label: '尝试解决' },
                    { v: 'unsolved', label: '未解决' },
                    { v: 'favorite', label: '我的收藏' },
                  ]"
                  :key="opt.v"
                  class="filter-item"
                  :class="{ active: statusFilter === opt.v }"
                  @click="statusFilter = opt.v as any"
                >
                  {{ opt.label }}
                </button>
              </div>
            </section>
            <section>
              <div class="ui-section-title mb-2 text-sm">难度</div>
              <div class="flex flex-col gap-1">
                <button
                  class="filter-item"
                  :class="{ active: difficultyFilter === '' }"
                  @click="difficultyFilter = ''"
                >
                  全部难度
                </button>
                <button
                  v-for="d in ['简单', '中等', '困难']"
                  :key="d"
                  class="filter-item"
                  :class="{ active: difficultyFilter === d }"
                  @click="difficultyFilter = difficultyFilter === d ? '' : (d as any)"
                >
                  <span :class="difficultyClass(d)" class="!px-2 !py-0">{{ d }}</span>
                </button>
              </div>
            </section>
            <section>
              <div class="ui-section-title mb-2 text-sm">分类</div>
              <div class="filter-scroll flex max-h-72 flex-col gap-1 overflow-y-auto pr-1">
                <button class="filter-item" :class="{ active: categoryFilter === '' }" @click="categoryFilter = ''">全部分类</button>
                <button
                  v-for="c in categories"
                  :key="c.key"
                  class="filter-item"
                  :class="{ active: categoryFilter === c.key }"
                  @click="categoryFilter = categoryFilter === c.key ? '' : c.key"
                >
                  {{ c.label }}
                </button>
              </div>
            </section>
          </div>
        </aside>

        <!-- 右侧内容 -->
        <section class="min-w-0 flex-1">
          <div class="problem-intro-card mb-4">
            <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
              <div>
                <h1 class="text-2xl font-semibold text-[var(--color-foreground)]">在线题库</h1>
                <p class="ui-section-sub mt-1">精选编程题目，持续提升你的编程能力。</p>
              </div>
              <div class="relative w-full xl:w-64">
                <Icon icon="material-symbols:search" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
                <input
                  v-model="searchQuery"
                  type="text"
                  class="ui-input h-10 pl-9"
                  placeholder="搜索题号、名称或标签"
                />
              </div>
            </div>

            <div data-testid="problem-toolbar" class="problem-toolbar mt-5">
              <div class="ui-segmented" role="group" aria-label="题目状态筛选">
                <button
                  type="button"
                  class="ui-segmented-item"
                  :class="{ 'is-active': statusFilter === '' }"
                  :aria-pressed="statusFilter === ''"
                  @click="statusFilter = ''"
                >
                  全部题目
                </button>
                <button
                  type="button"
                  class="ui-segmented-item"
                  :class="{ 'is-active': statusFilter === 'favorite' }"
                  :aria-pressed="statusFilter === 'favorite'"
                  @click="statusFilter = 'favorite'"
                >
                  我的收藏
                </button>
                <button
                  type="button"
                  class="ui-segmented-item"
                  :class="{ 'is-active': statusFilter === 'unsolved' }"
                  :aria-pressed="statusFilter === 'unsolved'"
                  @click="statusFilter = 'unsolved'"
                >
                  未解决
                </button>
                <button
                  type="button"
                  class="ui-segmented-item"
                  :class="{ 'is-active': statusFilter === 'solved' }"
                  :aria-pressed="statusFilter === 'solved'"
                  @click="statusFilter = 'solved'"
                >
                  已解决
                </button>
              </div>
              <div class="flex items-center gap-2">
                <select v-model="sortMode" class="problem-sort" aria-label="题目排序">
                  <option value="latest">按最新发布</option>
                  <option value="number">按题号排序</option>
                </select>
                <button class="ui-btn ui-btn-primary ui-btn-sm" @click="openRandomProblem">
                  <Icon icon="material-symbols:shuffle-rounded" class="h-4 w-4" />
                  随机一题
                </button>
              </div>
            </div>
          </div>

          <!-- 移动端筛选 -->
          <div class="ui-segmented ui-segmented-fill mb-4 lg:hidden" role="group" aria-label="难度与收藏筛选">
            <button
              type="button"
              class="ui-segmented-item"
              :class="{ 'is-active': difficultyFilter === '' }"
              :aria-pressed="difficultyFilter === ''"
              @click="difficultyFilter = ''"
            >
              全部
            </button>
            <button
              v-for="d in ['简单', '中等', '困难']"
              :key="d"
              type="button"
              class="ui-segmented-item"
              :class="{ 'is-active': difficultyFilter === d }"
              :aria-pressed="difficultyFilter === d"
              @click="difficultyFilter = difficultyFilter === d ? '' : (d as any)"
            >
              {{ d }}
            </button>
            <button
              type="button"
              class="ui-segmented-item"
              :class="{ 'is-active': statusFilter === 'favorite' }"
              :aria-pressed="statusFilter === 'favorite'"
              @click="statusFilter = statusFilter === 'favorite' ? '' : 'favorite'"
            >
              收藏
            </button>
          </div>

          <p v-if="!isLoading && !loadError && filteredProblems.length" class="problem-list-caption">
            共 {{ problems.length }} 道题目<template v-if="filteredProblems.length !== problems.length">，当前筛选 {{ filteredProblems.length }} 道</template>
          </p>

          <div class="problem-list" :class="{ 'has-stats': hasAnyStats }">
            <div v-if="isLoading" class="space-y-2 p-4">
              <div v-for="i in 6" :key="i" class="ui-skeleton h-10 w-full"></div>
            </div>

            <div v-else-if="loadError" class="problem-list__empty">
              <Icon icon="material-symbols:cloud-off-rounded" class="problem-list__empty-icon is-error" />
              <p class="problem-list__empty-title">加载失败</p>
              <p>{{ loadError }}</p>
              <button class="ui-btn ui-btn-primary ui-btn-sm" @click="loadProblems">重新加载</button>
            </div>

            <div v-else-if="filteredProblems.length === 0" class="problem-list__empty">
              <Icon icon="material-symbols:search-off" class="problem-list__empty-icon" />
              <p class="problem-list__empty-title">没有找到匹配的题目</p>
              <button class="ui-btn ui-btn-secondary ui-btn-sm" @click="resetFilters">清除筛选</button>
            </div>

            <template v-else>
              <div v-for="p in filteredProblems" :key="p.id" class="problem-row">
                <button type="button" class="problem-row__body" @click="openProblem(p.id)">
                  <span class="problem-row__status">
                    <Icon
                      v-if="p.isAccepted"
                      icon="material-symbols:check-circle-rounded"
                      class="problem-row__glyph is-done"
                    />
                    <Icon
                      v-else-if="p.isAttempted"
                      icon="material-symbols:pending"
                      class="problem-row__glyph is-tried"
                    />
                    <Icon v-else icon="material-symbols:radio-button-unchecked" class="problem-row__glyph is-todo" />
                    <span class="sr-only">{{ rowStatusText(p) }}</span>
                  </span>
                  <span class="problem-row__text">
                    <span class="problem-row__headline">
                      <span class="problem-row__number">#{{ p.sourceNumber ?? p.id }}</span>
                      <span class="problem-row__name">{{ p.title }}</span>
                    </span>
                    <span v-if="p.tags.length" class="problem-row__tags">{{ p.tags.slice(0, 3).join(' · ') }}</span>
                  </span>
                  <span class="problem-row__detail">
                    <span :class="difficultyClass(p.difficulty)">{{ p.difficulty }}</span>
                    <span class="problem-row__stats">
                      <span v-if="p.acceptRate != null">通过率 {{ p.acceptRate }}%</span>
                      <span v-if="p.acceptRate != null && p.stat.submissions" class="problem-row__dot" aria-hidden="true">·</span>
                      <span v-if="p.stat.submissions">{{ p.stat.submissions }} 次提交</span>
                    </span>
                  </span>
                </button>
                <button
                  type="button"
                  class="problem-row__star"
                  :class="{ 'is-on': isFavorited(p.id) }"
                  :aria-pressed="isFavorited(p.id)"
                  :aria-label="isFavorited(p.id) ? `取消收藏 ${p.title}` : `收藏 ${p.title}`"
                  @click="toggleFavorite(p, $event)"
                >
                  <Icon
                    :icon="isFavorited(p.id) ? 'material-symbols:star-rounded' : 'material-symbols:star-outline-rounded'"
                    class="h-[19px] w-[19px]"
                  />
                </button>
                <Icon class="problem-row__chevron" icon="material-symbols:chevron-right-rounded" aria-hidden="true" />
              </div>
            </template>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
@reference 'tailwindcss';

.filter-item {
  @apply flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors;
  color: var(--color-muted-foreground);
}
.problem-filter-card,
.problem-intro-card {
  @apply rounded-md border border-[var(--color-border)] bg-[var(--color-surface)] p-4 dark:border-[var(--color-border)] dark:bg-[var(--color-surface)];
}
.problem-intro-card {
  @apply p-5;
}
.problem-toolbar {
  @apply flex flex-col gap-3 border-t border-[var(--color-border)] pt-4 sm:flex-row sm:items-center sm:justify-between dark:border-[var(--color-border)];
}
/* 筛选项样式来自全局 .ui-segmented */
.problem-sort {
  @apply h-8 rounded-md border border-[var(--color-border)] bg-[var(--color-surface)] px-2.5 text-xs font-medium text-[var(--color-muted-foreground)] outline-none transition-colors focus:border-[var(--color-accent)] focus:ring-1 focus:ring-[var(--color-ring)]/25 dark:border-[var(--color-border-strong)] dark:bg-[var(--color-surface)] dark:text-[var(--color-foreground)];
}
html:not(.dark) .filter-item:hover {
  background: var(--color-muted);
}
.dark .filter-item {
  color: var(--color-foreground);
}
.dark .filter-item:hover {
  background: var(--color-surface-muted);
}
.filter-item.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
}
.dark .filter-item.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
}
/* ---- 题库列表：iOS 分组列表。分隔线内缩到正文起始处，尾部为细节文本与展开指示 ---- */
.problem-list-caption {
  margin: 0 0 0.5rem;
  padding: 0 0.25rem;
  font-size: 12px;
  font-weight: 500;
  color: var(--color-muted-foreground);
}
.problem-list {
  overflow: hidden;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
}
.problem-list__empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 3.5rem 1rem;
  text-align: center;
  font-size: 14px;
  color: var(--color-muted-foreground);
}
.problem-list__empty-icon {
  width: 32px;
  height: 32px;
  color: var(--color-muted-foreground);
}
.problem-list__empty-icon.is-error {
  color: var(--color-danger);
}
.problem-list__empty-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-foreground);
}
.problem-row {
  /* 1rem 行内边距 + 1.5rem 状态列 + 0.75rem 列间距 */
  --row-inset: 3.25rem;
  position: relative;
  display: flex;
  align-items: center;
  transition: background-color 0.18s ease;
}
.problem-row + .problem-row::before {
  content: "";
  position: absolute;
  top: 0;
  left: var(--row-inset);
  right: 0.5rem;
  height: 1px;
  background: var(--color-border);
  pointer-events: none;
}
.problem-row:hover {
  background: var(--color-surface-muted);
}
.problem-row:active {
  background: var(--color-muted);
}
.problem-row__body {
  display: grid;
  flex: 1 1 auto;
  grid-template-columns: 1.5rem minmax(0, 1fr) auto;
  align-items: center;
  gap: 0.75rem;
  min-width: 0;
  min-height: 64px;
  padding: 0.625rem 0.5rem 0.625rem 1rem;
  border: 0;
  background: transparent;
  text-align: left;
  cursor: pointer;
}
.problem-row__body:focus-visible {
  outline-offset: -2px;
}
.problem-row__status {
  display: flex;
  justify-content: center;
}
.problem-row__glyph {
  width: 20px;
  height: 20px;
}
.problem-row__glyph.is-done {
  color: var(--color-signal);
}
.problem-row__glyph.is-tried {
  color: var(--color-warning);
}
.problem-row__glyph.is-todo {
  color: var(--color-border-strong);
}
.problem-row__text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.problem-row__headline {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  min-width: 0;
}
.problem-row__number {
  flex-shrink: 0;
  font-family: var(--font-mono);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  color: var(--color-muted-foreground);
}
.problem-row__name {
  overflow: hidden;
  font-size: 15px;
  font-weight: 500;
  letter-spacing: -0.01em;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--color-foreground);
}
.problem-row__tags {
  overflow: hidden;
  font-size: 12.5px;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--color-muted-foreground);
}
.problem-row__detail {
  display: flex;
  flex-shrink: 0;
  align-items: center;
}
.problem-row__stats {
  display: none;
  align-items: center;
  justify-content: flex-end;
  gap: 0.375rem;
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  color: var(--color-muted-foreground);
}
.problem-row__dot {
  opacity: 0.6;
}
.problem-row__star {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-muted-foreground);
  cursor: pointer;
  transition:
    background-color 0.18s ease,
    color 0.18s ease;
}
.problem-row__star:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
.problem-row__star.is-on {
  color: var(--color-warning);
}
.problem-row__chevron {
  flex-shrink: 0;
  width: 18px;
  height: 18px;
  margin-right: 0.5rem;
  color: var(--color-muted-foreground);
  opacity: 0.45;
}
/* 桌面端把难度标签与统计文本一起贴到行的尾部 */
@media (min-width: 640px) {
  .problem-row__detail {
    justify-content: flex-end;
    gap: 0.875rem;
  }
  /* 固定统计列宽度，让「通过率」在多行之间保持同一条竖向基线 */
  .problem-list.has-stats .problem-row__stats {
    display: flex;
    flex: 0 0 auto;
    width: 11rem;
  }
}
@media (pointer: coarse) {
  .problem-row__star {
    width: 44px;
    height: 44px;
  }
}

.filter-scroll::-webkit-scrollbar {
  width: 6px;
}
.filter-scroll::-webkit-scrollbar-thumb {
  background: var(--color-muted);
  border-radius: 3px;
}
.dark .filter-scroll::-webkit-scrollbar-thumb {
  background: var(--color-muted);
}
</style>
