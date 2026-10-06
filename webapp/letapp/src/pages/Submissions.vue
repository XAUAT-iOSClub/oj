<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { Icon } from '@iconify/vue';
import {
  listMySubmissions,
  type SubmissionHistoryItem,
} from '../services/api';
import { formatDateTime as formatCSTDateTime } from '../utils/time';

const router = useRouter();

const submissions = ref<SubmissionHistoryItem[]>([]);
const loading = ref(true);
const loadError = ref('');
const currentPage = ref(1);
const perPage = 20;
const total = ref(0);

const totalPages = computed(() => Math.max(Math.ceil(total.value / perPage), 1));

const statusInfo: Record<string, { label: string; color: string }> = {
  AC: { label: '通过', color: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300' },
  WA: { label: '答案错误', color: 'bg-rose-100 text-rose-700 dark:bg-rose-950 dark:text-rose-300' },
  CE: { label: '编译错误', color: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300' },
  TLE: { label: '超时', color: 'bg-orange-100 text-orange-700 dark:bg-orange-950 dark:text-orange-300' },
  RE: { label: '运行错误', color: 'bg-violet-100 text-violet-700 dark:bg-violet-950 dark:text-violet-300' },
  Running: { label: '判题中', color: 'bg-accent-soft text-accent-soft-foreground' },
  Pending: { label: '排队中', color: 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300' },
};

const getStatusInfo = (status: string) =>
  statusInfo[status] ?? { label: status || '未知', color: 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300' };

const formatDate = (dateString: string | null) => {
  if (!dateString) return '—';
  return formatCSTDateTime(dateString, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const loadSubmissions = async () => {
  loading.value = true;
  loadError.value = '';
  try {
    const result = await listMySubmissions(currentPage.value, perPage);
    submissions.value = result.data;
    total.value = result.total;
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : '加载提交记录失败';
    submissions.value = [];
    total.value = 0;
  } finally {
    loading.value = false;
  }
};

const handlePageChange = (page: number) => {
  currentPage.value = Math.min(Math.max(page, 1), totalPages.value);
  loadSubmissions();
};

const openProblem = (problemId: number) => {
  router.push(`/problems/${problemId}`);
};

// 筛选
const statusFilter = ref('');
const languageFilter = ref('');
const languages = computed(() => {
  const set = new Set(submissions.value.map((s) => s.language).filter(Boolean));
  return Array.from(set);
});
const filteredSubmissions = computed(() => {
  return submissions.value.filter((s) => {
    if (statusFilter.value && s.status !== statusFilter.value) return false;
    if (languageFilter.value && s.language !== languageFilter.value) return false;
    return true;
  });
});

onMounted(loadSubmissions);
</script>

<template>
  <div class="submissions-page min-h-[calc(100vh-var(--header-h,4rem))] bg-[var(--color-background)]">
    <div class="app-container py-6">
      <!-- 标题区 88px -->
      <div class="mb-4 flex items-center justify-between" style="min-height:88px">
        <div>
          <h1 class="text-2xl font-bold text-[var(--color-foreground)]">提交记录</h1>
          <p class="ui-section-sub mt-1">每次判题都会留档，点击记录可回到对应题目。</p>
        </div>
        <span class="ui-badge ui-badge-blue">共 {{ total }} 次提交</span>
      </div>

      <!-- 工具栏 56px -->
      <div class="ui-card mb-4 flex items-center gap-3 !p-3" style="height:56px">
        <div class="relative flex-1 sm:max-w-xs">
          <Icon icon="material-symbols:filter-list-rounded" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
          <select
            v-model="statusFilter"
            class="h-10 w-full appearance-none rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] pl-9 pr-8 text-sm text-[var(--color-foreground)] outline-none transition focus:border-[var(--color-accent)] dark:border-[var(--color-border)] dark:bg-[var(--color-background)] dark:text-[var(--color-foreground)]"
          >
            <option value="">全部状态</option>
            <option v-for="(info, key) in statusInfo" :key="key" :value="key">{{ info.label }}</option>
          </select>
          <Icon icon="material-symbols:expand-more" class="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
        </div>
        <div v-if="languages.length" class="relative flex-1 sm:max-w-xs">
          <Icon icon="material-symbols:code-rounded" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
          <select
            v-model="languageFilter"
            class="h-10 w-full appearance-none rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] pl-9 pr-8 text-sm text-[var(--color-foreground)] outline-none transition focus:border-[var(--color-accent)] dark:border-[var(--color-border)] dark:bg-[var(--color-background)] dark:text-[var(--color-foreground)]"
          >
            <option value="">全部语言</option>
            <option v-for="lang in languages" :key="lang" :value="lang">{{ lang }}</option>
          </select>
          <Icon icon="material-symbols:expand-more" class="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
        </div>
        <div class="ml-auto text-sm text-[var(--color-muted-foreground)]">
          共 <span class="font-bold text-[var(--color-foreground)]">{{ filteredSubmissions.length }}</span> 条
        </div>
      </div>

      <!-- 加载骨架 -->
      <div v-if="loading" class="space-y-2">
        <div v-for="i in 6" :key="i" class="ui-skeleton h-14 w-full rounded-md"></div>
      </div>

      <!-- 错误 -->
      <div v-else-if="loadError" class="ui-empty">
        <Icon icon="material-symbols:cloud-off-rounded" class="mb-2 h-10 w-10 text-rose-400" />
        <p class="font-bold text-[var(--color-foreground)]">加载失败</p>
        <p class="text-sm text-[var(--color-muted-foreground)]">{{ loadError }}</p>
        <button class="ui-btn ui-btn-secondary ui-btn-sm mt-2" @click="loadSubmissions">重新加载</button>
      </div>

      <!-- 空态 -->
      <div v-else-if="filteredSubmissions.length === 0" class="ui-empty">
        <Icon icon="material-symbols:inbox-rounded" class="mb-2 h-10 w-10 text-[var(--color-muted-foreground)]" />
        <p class="font-bold text-[var(--color-foreground)]">还没有提交记录</p>
        <p class="text-sm text-[var(--color-muted-foreground)]">去题库挑一道题，写下你的第一份代码吧。</p>
        <button class="ui-btn ui-btn-primary ui-btn-sm mt-2" @click="router.push('/problems')">前往题库</button>
      </div>

      <!-- 表格 -->
      <div v-else class="overflow-x-auto">
        <table class="ui-table w-full">
          <thead>
            <tr>
              <th style="width:100px">提交 ID</th>
              <th>题目</th>
              <th style="width:140px" class="text-center">状态</th>
              <th style="width:100px" class="text-center">语言</th>
              <th style="width:100px" class="text-center">运行时间</th>
              <th style="width:160px" class="text-center">提交时间</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in filteredSubmissions"
              :key="item.id"
              class="cursor-pointer"
              @click="openProblem(item.problem_id)"
            >
              <td class="font-mono text-xs text-[var(--color-muted-foreground)]">#{{ item.id }}</td>
              <td>
                <span class="truncate font-bold text-[var(--color-foreground)]">{{ item.problem_title }}</span>
                <span v-if="item.difficulty" class="ui-diff ml-2" :class="item.difficulty === '简单' ? 'ui-diff-easy' : item.difficulty === '中等' ? 'ui-diff-mid' : 'ui-diff-hard'">{{ item.difficulty }}</span>
              </td>
              <td class="text-center">
                <span class="ui-badge" :class="getStatusInfo(item.status).color">{{ getStatusInfo(item.status).label }}</span>
              </td>
              <td class="text-center text-sm text-[var(--color-muted-foreground)]">{{ item.language }}</td>
              <td class="text-center text-sm text-[var(--color-muted-foreground)]">{{ item.time_used != null ? item.time_used + 'ms' : '—' }}</td>
              <td class="text-center text-xs text-[var(--color-muted-foreground)]">{{ formatDate(item.created_at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 分页 -->
      <div v-if="totalPages > 1" class="mt-4 flex items-center justify-between">
        <p class="text-sm text-[var(--color-muted-foreground)]">
          第 <span class="font-bold">{{ currentPage }}</span> 页，共 <span class="font-bold">{{ totalPages }}</span> 页
        </p>
        <div class="ui-pager">
          <button class="ui-pager-item" :disabled="currentPage === 1" @click="handlePageChange(currentPage - 1)">上一页</button>
          <button
            v-for="page in totalPages"
            :key="page"
            class="ui-pager-item"
            :class="{ 'ui-pager-item-active': currentPage === page }"
            @click="handlePageChange(page)"
          >{{ page }}</button>
          <button class="ui-pager-item" :disabled="currentPage === totalPages" @click="handlePageChange(currentPage + 1)">下一页</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@reference 'tailwindcss';
</style>
