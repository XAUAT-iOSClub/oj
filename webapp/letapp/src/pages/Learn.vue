<script setup lang="ts">
import { computed, defineAsyncComponent, onMounted, onUnmounted, ref, watch } from 'vue';
import { Icon } from '@iconify/vue';
import { useRoute, useRouter } from 'vue-router';
import { sortNodesFoldersFirst } from '../utils/treeSort';
import { fileIcon, fileTypeLabel } from '../utils/learnFile';
import { formatRelativeTime } from '../utils/time';
import type { RecentItem } from '../components/RecentPanel.vue';
import { useAuthStore } from '../stores/auth';
import { clearLearnHistory, listLearnHistory, recordLearnHistory } from '../services/api';

const MarkdownComponent = defineAsyncComponent(
  () => import('../components/MarkdownComponent.vue'),
);
const LearnSidebar = defineAsyncComponent(
  () => import('../components/LearnSidebar.vue'),
);
const RecentPanel = defineAsyncComponent(
  () => import('../components/RecentPanel.vue'),
);

/** ====== 数据类型 ====== */
interface TreeNode {
  id: string;
  name: string;
  type: 'folder' | 'file';
  path: string;
  children?: TreeNode[];
  size?: number;
  mtime?: number;
}

interface MarkdownData {
  content: string;
  title: string;
  path: string;
  mtime: number;
  /** 源文件自带 `# 标题` 时为 true —— 正文会渲染这个标题，页面不再补一个。 */
  hasOwnHeading: boolean;
}

interface HeadingItem {
  level: number;
  text: string;
  id: string;
}

interface BreadcrumbItem {
  name: string;
  path: string;
}

/** ====== 路由 ====== */
const route = useRoute();
const router = useRouter();
const authStore = useAuthStore();

/** ====== 状态 ====== */
const treeData = ref<TreeNode | null>(null);
const currentFile = ref<MarkdownData | null>(null);
const isLoadingTree = ref(false);
const isLoadingDoc = ref(false);
const error = ref('');
/** 正文大纲由 MarkdownComponent 抛出，避免在页面里重复解析一遍标题。 */
const mdHeadings = ref<HeadingItem[]>([]);
const mdActiveHeading = ref('');

/** 当前在中间区域浏览的文件夹路径（'' = 根目录） */
const browsePath = ref('');
const middleSearch = ref('');
const recentList = ref<RecentItem[]>([]);
const mobileSidebarOpen = ref(false);
const mobileMenuButton = ref<HTMLButtonElement | null>(null);

/** ====== 路径工具：学习资料以同源静态文件方式提供（public/learn-dist） ====== */
function encodePath(p: string): string {
  return p.split('/').map((s) => encodeURIComponent(s)).join('/');
}

const learnBase = '/learn-dist';

const PREFIX_RE = /^\d+[-_.\s]+/;
function cleanName(name: string): string {
  return name.replace(PREFIX_RE, '').replace(/\.md$/, '');
}
function cleanPath(path: string): string {
  return path.split('/').filter(Boolean).map(cleanName).join(' / ');
}

/** ====== 树查找 / 面包屑 ====== */
function getNodeByPath(path: string): TreeNode | null {
  if (!treeData.value) return null;
  if (!path) return treeData.value;
  const parts = path.split('/').filter(Boolean);
  let node: TreeNode | null = treeData.value;
  let acc = '';
  for (const part of parts) {
    if (!node || !node.children) return null;
    acc = acc ? acc + '/' + part : part;
    node = node.children.find((c) => c.path === acc) || null;
    if (!node) return null;
  }
  return node;
}

function buildBreadcrumb(path: string): BreadcrumbItem[] {
  if (!treeData.value || !path) return [];
  const parts = path.split('/').filter(Boolean);
  const crumbs: BreadcrumbItem[] = [];
  let node: TreeNode | null = treeData.value;
  let acc = '';
  for (const part of parts) {
    if (!node || !node.children) break;
    acc = acc ? acc + '/' + part : part;
    node = node.children.find((c) => c.path === acc) || null;
    if (!node) break;
    crumbs.push({ name: node.name, path: acc });
  }
  return crumbs;
}

/** ====== 加载目录树（静态 manifest） ====== */
async function loadTree() {
  isLoadingTree.value = true;
  error.value = '';
  try {
    const res = await fetch(`${learnBase}/tree.json`, { cache: 'no-cache' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const json = await res.json();
    treeData.value = json || null;
  } catch (e: any) {
    error.value = `目录加载失败: ${e.message}`;
  } finally {
    isLoadingTree.value = false;
  }
}

/** ====== 加载 Markdown 文件（静态文件） ====== */
function fallbackTitle(filePath: string): string {
  return cleanName(filePath.split('/').pop() || filePath);
}

async function fetchMarkdown(filePath: string): Promise<MarkdownData> {
  const res = await fetch(`${learnBase}/${encodePath(filePath)}`, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const text = await res.text();
  // 标题与"是否自带标题"取自同一个匹配结果，两者不可能不一致。
  const headingMatch = text.match(/^#\s+(.+)$/m);
  const headingText = headingMatch?.[1]?.trim();
  return {
    content: text,
    title: headingText || fallbackTitle(filePath),
    path: filePath,
    mtime: 0,
    hasOwnHeading: Boolean(headingText),
  };
}

/** 同一时刻只认最后一次加载，避免连点两个文件时后到的旧响应覆盖新内容。 */
let loadVersion = 0;

async function loadFile(filePath: string) {
  const version = ++loadVersion;
  isLoadingDoc.value = true;
  error.value = '';
  try {
    const data = await fetchMarkdown(filePath);
    if (version !== loadVersion) return;
    currentFile.value = data;
    router.replace({ query: { path: filePath } });
    pushRecent(data);
  } catch (e: any) {
    if (version !== loadVersion) return;
    error.value = `文件加载失败：${e.message}`;
  } finally {
    if (version === loadVersion) isLoadingDoc.value = false;
  }
}

/** 打开中间区域的资料 */
function openFile(filePath: string) {
  loadFile(filePath);
  closeMobileSidebar(false);
}

/** ====== 重新扫描（重新拉取 manifest） ====== */
async function rescanTree() {
  isLoadingTree.value = true;
  try {
    const res = await fetch(`${learnBase}/tree.json?t=${Date.now()}`);
    if (res.ok) treeData.value = await res.json();
  } catch { /* ignore */ }
  finally {
    isLoadingTree.value = false;
  }
}

/** ====== 导航：文件夹浏览 ====== */
function navigateToFolder(path: string) {
  browsePath.value = path;
  middleSearch.value = '';
  closeMobileSidebar(false);
}

/** 关闭详情回到浏览 */
function backToBrowse() {
  currentFile.value = null;
  mdHeadings.value = [];
  mdActiveHeading.value = '';
  router.replace({ query: {} });
}

const currentLocation = computed(() => (currentFile.value ? currentFile.value.path : browsePath.value));

/** ====== 侧边栏事件 ====== */
function handleSidebarSelect(path: string) {
  loadFile(path);
}
function handleSidebarHeading(id: string) {
  const el = document.getElementById(id);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
function handleSidebarBrowse(path: string) {
  navigateToFolder(path);
}

/** MarkdownComponent 抛出的正文大纲与当前小节 */
function handleHeadings(headings: HeadingItem[]) {
  mdHeadings.value = headings;
}
function handleActiveHeading(id: string) {
  mdActiveHeading.value = id;
}

/** ====== 导出 Markdown ====== */
function downloadCurrentMarkdown() {
  if (!currentFile.value) return;
  const blob = new Blob([currentFile.value.content], { type: 'text/markdown;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${currentFile.value.title || 'document'}.md`;
  a.click();
  URL.revokeObjectURL(url);
}

/** ====== 统计 ====== */
function countFiles(node: TreeNode | null): number {
  if (!node) return 0;
  if (node.type === 'file') return 1;
  if (!node.children) return 0;
  return node.children.reduce((sum, c) => sum + countFiles(c), 0);
}
const totalFileCount = computed(() => countFiles(treeData.value));

/** ====== 中间区域内容 ====== */
const currentBrowseNode = computed(() => getNodeByPath(browsePath.value));
const breadcrumb = computed(() => buildBreadcrumb(browsePath.value));

const sortedChildren = computed(() => {
  const node = currentBrowseNode.value;
  if (!node?.children) return [];
  return sortNodesFoldersFirst(node.children);
});

const folderChildren = computed(() => sortedChildren.value.filter((c) => c.type === 'folder'));
const fileChildren = computed(() => sortedChildren.value.filter((c) => c.type === 'file'));

function matchesSearch(node: TreeNode, q: string): boolean {
  return cleanName(node.name).toLowerCase().includes(q);
}

const filteredFolders = computed(() => {
  const q = middleSearch.value.trim().toLowerCase();
  if (!q) return folderChildren.value;
  return folderChildren.value.filter((c) => matchesSearch(c, q));
});
const filteredFiles = computed(() => {
  const q = middleSearch.value.trim().toLowerCase();
  if (!q) return fileChildren.value;
  return fileChildren.value.filter((c) => matchesSearch(c, q));
});

const isEmptyBrowse = computed(
  () => !filteredFolders.value.length && !filteredFiles.value.length,
);

/** 行尾次要信息：修改时间 + 类型，缺时间时只留类型。 */
function entryMeta(node: TreeNode): string {
  const parts: string[] = [];
  if (node.mtime) parts.push(formatRelativeTime(node.mtime * 1000));
  parts.push(fileTypeLabel(node.name));
  return parts.join(' · ');
}

/** ====== 详情页：标题去重 ====== */
// 源文件自带 `# 标题` 时，MarkdownComponent 会把它渲染成正文标题，
// 此时页面不再重复输出一遍 h1；只有回退到文件名时才由页面补标题。
const docHasOwnTitle = computed(() => currentFile.value?.hasOwnHeading === true);

/** ====== 最近浏览（登录用户数据库） ====== */
async function loadRecent() {
  recentList.value = [];
  if (!authStore.isAuthenticated || !treeData.value) return;
  try {
    const response = await listLearnHistory();
    recentList.value = response.data.map((item) => {
      const node = getNodeByPath(item.resource_id);
      const visitedAt = item.browsed_at ? new Date(item.browsed_at).getTime() : Date.now();
      return {
        path: item.resource_id,
        title: node ? cleanName(node.name) : cleanPath(item.resource_id),
        dir: cleanPath(item.resource_id.split('/').slice(0, -1).join('/')),
        mtime: Math.floor(visitedAt / 1000),
        visitedAt,
      };
    }).slice(0, 6);
  } catch {
    // 历史记录加载失败不影响资料浏览。
  }
}
function pushRecent(file: MarkdownData) {
  if (!authStore.isAuthenticated) return;
  const parent = file.path.split('/').slice(0, -1).join('/');
  const item: RecentItem = {
    path: file.path,
    title: file.title,
    dir: cleanPath(parent),
    mtime: file.mtime || Math.floor(Date.now() / 1000),
    visitedAt: Date.now(),
  };
  const next = recentList.value.filter((r) => r.path !== file.path);
  next.unshift(item);
  recentList.value = next.slice(0, 6);
  void recordLearnHistory(file.path).catch(() => { /* 浏览记录失败不影响阅读 */ });
}
function clearRecent() {
  if (!authStore.isAuthenticated) return;
  recentList.value = [];
  void clearLearnHistory().catch(() => { /* 清空失败时保持当前界面状态 */ });
}
const continueItem = computed(() => recentList.value[0] || null);

watch(() => authStore.isAuthenticated, (authenticated) => {
  if (authenticated) void loadRecent();
  else recentList.value = [];
});

/** ====== 详情页面包屑 ====== */
const fileBreadcrumb = computed<BreadcrumbItem[]>(() => {
  if (!currentFile.value) return [];
  const parent = currentFile.value.path.split('/').slice(0, -1).join('/');
  return buildBreadcrumb(parent);
});

/** ====== 响应式 ====== */
const windowWidth = ref(typeof window !== 'undefined' ? window.innerWidth : 1440);
function getRecentMode(w: number): 'desktop' | 'tablet' | 'mobile' {
  if (w >= 1024) return 'desktop';
  if (w >= 768) return 'tablet';
  return 'mobile';
}

/** 右侧“最近浏览”收起状态（按设备尺寸分别记忆） */
const RECENT_COLLAPSED_KEY = 'learn_recent_collapsed_v1';
const storedCollapsed = ref<Record<string, boolean>>({});
function loadCollapsed() {
  try {
    const raw = localStorage.getItem(RECENT_COLLAPSED_KEY);
    if (raw) storedCollapsed.value = JSON.parse(raw) || {};
  } catch { /* ignore */ }
}
function saveCollapsed() {
  try { localStorage.setItem(RECENT_COLLAPSED_KEY, JSON.stringify(storedCollapsed.value)); } catch { /* ignore */ }
}

const recentMode = computed(() => getRecentMode(windowWidth.value));
const showRecent = computed(() => authStore.isAuthenticated && recentMode.value !== 'mobile');
const recentCollapsed = ref(false);
function defaultCollapsedFor(mode: string): boolean {
  // 平板默认收起，桌面默认展开
  return mode === 'tablet';
}
function syncCollapsed() {
  const m = recentMode.value;
  if (m === 'mobile') { recentCollapsed.value = false; return; }
  recentCollapsed.value = storedCollapsed.value[m] ?? defaultCollapsedFor(m);
}
function toggleRecent() {
  const m = recentMode.value;
  if (m === 'mobile') return;
  recentCollapsed.value = !recentCollapsed.value;
  storedCollapsed.value = { ...storedCollapsed.value, [m]: recentCollapsed.value };
  saveCollapsed();
}

function onResize() {
  windowWidth.value = window.innerWidth;
  if (windowWidth.value >= 1024) closeMobileSidebar(false);
  syncCollapsed();
}
function toggleMobileSidebar() {
  if (mobileSidebarOpen.value) closeMobileSidebar(true);
  else mobileSidebarOpen.value = true;
}
/** 关闭移动端目录抽屉；restoreFocus 时把焦点还给触发按钮。 */
function closeMobileSidebar(restoreFocus = false) {
  if (!mobileSidebarOpen.value) return;
  mobileSidebarOpen.value = false;
  if (restoreFocus) mobileMenuButton.value?.focus({ preventScroll: true });
}

/** 抽屉打开时按 Esc 关闭并把焦点送回触发按钮。 */
function onDrawerKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') closeMobileSidebar(true);
}
watch(mobileSidebarOpen, (open) => {
  document.body.style.overflow = open ? 'hidden' : '';
  if (open) window.addEventListener('keydown', onDrawerKeydown);
  else window.removeEventListener('keydown', onDrawerKeydown);
});

onMounted(async () => {
  window.addEventListener('resize', onResize);
  loadCollapsed();
  syncCollapsed();
  await loadTree();
  await loadRecent();
  const queryPath = route.query.path as string;
  if (queryPath) await loadFile(queryPath);
  else navigateToFolder('');
});

onUnmounted(() => {
  window.removeEventListener('resize', onResize);
  window.removeEventListener('keydown', onDrawerKeydown);
  document.body.style.overflow = '';
});
</script>

<template>
  <div class="learn-shell">

    <!-- 移动端遮罩 -->
    <div v-if="mobileSidebarOpen" class="sidebar-overlay" @click="closeMobileSidebar(true)" />

    <!-- ===== 主体三栏 ===== -->
    <div class="learn-body app-container-with-sidebar">

      <!-- 左侧资源目录 -->
      <aside
        v-if="treeData"
        class="learn-sidebar-col"
        :class="{ 'is-open': mobileSidebarOpen }"
      >
        <LearnSidebar
          :tree="treeData.children || []"
          :current-path="currentLocation"
          :headings="mdHeadings"
          :active-heading="mdActiveHeading"
          @select="handleSidebarSelect"
          @heading="handleSidebarHeading"
          @browse="handleSidebarBrowse"
          @rescan="rescanTree"
        />
      </aside>

      <!-- 中间主内容 -->
      <main class="learn-main-col">

        <!-- 加载中 -->
        <div v-if="isLoadingTree" class="learn-state">
          <Icon icon="svg-spinners:90-ring-with-bg" class="h-8 w-8 text-[var(--color-accent-text)]" aria-hidden="true" />
          <p>正在扫描学习资料目录…</p>
        </div>

        <!-- 错误 -->
        <div v-else-if="error && !treeData" class="learn-state">
          <Icon icon="material-symbols:error-outline" class="h-8 w-8 text-[var(--color-danger-text)]" aria-hidden="true" />
          <p class="is-error">{{ error }}</p>
          <button class="ui-btn ui-btn-secondary ui-btn-sm mt-3" @click="loadTree">重试</button>
        </div>

        <!-- ===== 浏览模式 ===== -->
        <template v-else-if="treeData && !currentFile">

          <header class="page-header">
            <div class="page-header-text">
              <h1 class="page-title">学习资源</h1>
              <p class="page-subtitle">
                按主题整理的学习笔记与资料，共 {{ totalFileCount }} 篇
              </p>
            </div>
            <button
              class="ui-btn ui-btn-secondary ui-btn-sm page-header-action"
              @click="router.push('/playground')"
            >
              <Icon icon="material-symbols:code" class="h-4 w-4" aria-hidden="true" />
              去编辑器练习
            </button>
          </header>

          <!-- 继续学习 -->
          <button
            v-if="continueItem"
            type="button"
            class="continue-banner"
            @click="openFile(continueItem.path)"
          >
            <Icon icon="material-symbols:play-circle-outline" class="continue-icon" aria-hidden="true" />
            <span class="continue-body">
              <span class="continue-label">继续学习</span>
              <span class="continue-title">{{ continueItem.title }}</span>
              <span class="continue-meta">{{ continueItem.dir }}</span>
            </span>
            <Icon icon="material-symbols:chevron-right" class="continue-arrow" aria-hidden="true" />
          </button>

          <!-- 工具条：面包屑 + 当前目录搜索 -->
          <div class="browse-toolbar">
            <button
              ref="mobileMenuButton"
              type="button"
              class="header-menu-btn"
              aria-label="打开资料目录"
              @click="toggleMobileSidebar"
            >
              <Icon icon="material-symbols:menu" class="h-5 w-5" aria-hidden="true" />
            </button>

            <nav v-if="breadcrumb.length" class="learn-breadcrumb" aria-label="目录层级">
              <button
                type="button"
                class="crumb"
                @click="navigateToFolder('')"
              >学习资源</button>
              <template v-for="(c, i) in breadcrumb" :key="c.path">
                <Icon icon="material-symbols:chevron-right" class="crumb-sep" aria-hidden="true" />
                <button
                  type="button"
                  class="crumb"
                  :class="{ 'crumb-current': i === breadcrumb.length - 1 }"
                  :aria-current="i === breadcrumb.length - 1 ? 'page' : undefined"
                  @click="navigateToFolder(c.path)"
                >{{ c.name }}</button>
              </template>
            </nav>

            <div class="toolbar-search">
              <Icon icon="material-symbols:search-rounded" class="toolbar-search-icon" aria-hidden="true" />
              <label class="sr-only" for="learn-dir-search">搜索当前目录中的资料</label>
              <input
                id="learn-dir-search"
                v-model="middleSearch"
                type="search"
                placeholder="搜索当前目录"
                class="toolbar-search-input"
              />
            </div>
          </div>

          <!-- 目录内容：只列当前目录 -->
          <div v-if="!isEmptyBrowse" class="entry-list">
            <button
              v-for="folder in filteredFolders"
              :key="folder.path"
              type="button"
              class="entry-row"
              @click="navigateToFolder(folder.path)"
            >
              <Icon icon="material-symbols:folder-outline" class="entry-icon" aria-hidden="true" />
              <span class="entry-name" :title="cleanName(folder.name)">{{ cleanName(folder.name) }}</span>
              <span class="entry-meta">{{ countFiles(folder) }} 篇</span>
              <Icon icon="material-symbols:chevron-right" class="entry-arrow" aria-hidden="true" />
            </button>

            <button
              v-for="f in filteredFiles"
              :key="f.path"
              type="button"
              class="entry-row"
              @click="openFile(f.path)"
            >
              <Icon :icon="fileIcon(f.name)" class="entry-icon" aria-hidden="true" />
              <span class="entry-name" :title="cleanName(f.name)">{{ cleanName(f.name) }}</span>
              <span class="entry-meta">{{ entryMeta(f) }}</span>
              <Icon icon="material-symbols:chevron-right" class="entry-arrow" aria-hidden="true" />
            </button>
          </div>

          <!-- 空状态 -->
          <div v-else class="ui-empty">
            <Icon icon="material-symbols:folder-off" class="h-7 w-7" aria-hidden="true" />
            <p>{{ middleSearch ? '当前目录没有匹配的资料' : '该目录下暂无资料' }}</p>
          </div>
        </template>

        <!-- ===== 详情模式 ===== -->
        <template v-else-if="currentFile">
          <div class="learn-detail-main">
            <!-- 工具条：面包屑 + 操作 -->
            <div class="detail-toolbar">
              <button
                ref="mobileMenuButton"
                type="button"
                class="header-menu-btn"
                aria-label="打开资料目录"
                @click="toggleMobileSidebar"
              >
                <Icon icon="material-symbols:menu" class="h-5 w-5" aria-hidden="true" />
              </button>

              <nav class="learn-breadcrumb" aria-label="目录层级">
                <button type="button" class="crumb" @click="backToBrowse">学习资源</button>
                <template v-for="c in fileBreadcrumb" :key="c.path">
                  <Icon icon="material-symbols:chevron-right" class="crumb-sep" aria-hidden="true" />
                  <button type="button" class="crumb" @click="navigateToFolder(c.path)">{{ c.name }}</button>
                </template>
                <Icon icon="material-symbols:chevron-right" class="crumb-sep" aria-hidden="true" />
                <span class="crumb crumb-current" aria-current="page">{{ currentFile.title }}</span>
              </nav>

              <div class="detail-actions">
                <button
                  type="button"
                  class="toolbar-icon-btn"
                  aria-label="导出 Markdown"
                  title="导出 Markdown"
                  @click="downloadCurrentMarkdown"
                >
                  <Icon icon="material-symbols:download-rounded" class="h-[18px] w-[18px]" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  class="toolbar-icon-btn"
                  aria-label="去编辑器练习"
                  title="去编辑器练习"
                  @click="router.push('/playground')"
                >
                  <Icon icon="material-symbols:code" class="h-[18px] w-[18px]" aria-hidden="true" />
                </button>
              </div>
            </div>

            <!-- 加载中 -->
            <div v-if="isLoadingDoc" class="learn-state">
              <Icon icon="svg-spinners:90-ring-with-bg" class="h-8 w-8 text-[var(--color-accent-text)]" aria-hidden="true" />
              <p>加载文档中…</p>
            </div>

            <!-- Markdown 内容 -->
            <article v-else class="learn-doc-container">
              <h1 v-if="!docHasOwnTitle" class="learn-doc-title">{{ currentFile.title }}</h1>
              <MarkdownComponent
                :source="currentFile.content"
                :show-nav="false"
                :show-heading-links="false"
                :base-dir="currentFile.path.split('/').slice(0, -1).join('/')"
                @navigate="loadFile"
                @headings="handleHeadings"
                @active-heading="handleActiveHeading"
              />
            </article>
          </div>
        </template>
      </main>

      <!-- 右侧最近浏览（可收起） -->
      <aside
        v-if="showRecent && treeData"
        class="learn-recent-col"
        :class="{ 'is-collapsed': recentCollapsed }"
      >
        <div class="recent-topbar">
          <span class="recent-title">最近浏览</span>
          <button
            v-if="recentList.length && !recentCollapsed"
            type="button"
            class="topbar-icon-btn"
            title="清空浏览记录"
            aria-label="清空浏览记录"
            @click="clearRecent"
          >
            <Icon icon="material-symbols:delete-outline" class="h-[18px] w-[18px]" aria-hidden="true" />
          </button>
          <button
            type="button"
            class="topbar-icon-btn"
            :title="recentCollapsed ? '展开最近浏览' : '收起最近浏览'"
            :aria-label="recentCollapsed ? '展开最近浏览' : '收起最近浏览'"
            :aria-expanded="!recentCollapsed"
            @click="toggleRecent"
          >
            <Icon
              :icon="recentCollapsed ? 'material-symbols:chevron-left' : 'material-symbols:chevron-right'"
              class="h-[18px] w-[18px]"
              aria-hidden="true"
            />
          </button>
        </div>
        <div v-show="!recentCollapsed" class="recent-scroll">
          <RecentPanel :items="recentList" @open="openFile" />
        </div>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.learn-shell {
  min-height: calc(100vh - var(--header-h, 4rem));
  background: var(--color-background);
}

/* ===== 主体：三栏，整页滚动，侧栏走 sticky 轨道 ===== */
.learn-body {
  align-items: flex-start;
  padding-top: 24px;
  padding-bottom: 40px;
}

.learn-sidebar-col {
  position: sticky;
  top: calc(var(--header-h, 4rem) + 24px);
  width: 260px;
  height: calc(100dvh - var(--header-h, 4rem) - 48px);
  flex-shrink: 0;
  overflow: hidden;
  border-right: 1px solid var(--color-border);
  background: var(--color-surface);
}

.learn-main-col {
  flex: 1;
  min-width: 0;
  padding-bottom: 24px;
}

.learn-recent-col {
  position: sticky;
  top: calc(var(--header-h, 4rem) + 24px);
  display: flex;
  width: 260px;
  height: calc(100dvh - var(--header-h, 4rem) - 48px);
  flex-shrink: 0;
  flex-direction: column;
  overflow: hidden;
  border-left: 1px solid var(--color-border);
  transition: width 0.2s ease;
}
.learn-recent-col.is-collapsed {
  width: 44px;
}

.recent-topbar {
  display: flex;
  flex-shrink: 0;
  align-items: center;
  gap: 2px;
  padding: 0 6px 6px 14px;
}
.learn-recent-col.is-collapsed .recent-topbar {
  justify-content: center;
  padding: 0 0 6px;
}
.recent-title {
  flex: 1;
  overflow: hidden;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--color-muted-foreground);
  white-space: nowrap;
}
.learn-recent-col.is-collapsed .recent-title {
  display: none;
}
.topbar-icon-btn {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border: none;
  border-radius: 6px;
  background: none;
  color: var(--color-muted-foreground);
  cursor: pointer;
  transition: color 0.15s ease, background-color 0.15s ease;
}
.topbar-icon-btn:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
.recent-scroll {
  width: 100%;
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 10px 16px 14px;
  scrollbar-width: thin;
  scrollbar-color: var(--color-border) transparent;
}
.recent-scroll::-webkit-scrollbar {
  width: 10px;
}
.recent-scroll::-webkit-scrollbar-track {
  background: transparent;
}
.recent-scroll::-webkit-scrollbar-thumb {
  border: 3px solid transparent;
  border-radius: 5px;
  background-color: var(--color-border);
  background-clip: content-box;
}
.recent-scroll::-webkit-scrollbar-thumb:hover {
  background-color: var(--color-muted-foreground);
  background-clip: content-box;
}

/* ===== 状态 ===== */
.learn-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 64px 0;
  color: var(--color-muted-foreground);
}
.learn-state p {
  margin: 12px 0 0;
  font-size: 13px;
}
.learn-state p.is-error {
  color: var(--color-danger-text);
}

/* ===== 页头 ===== */
.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 20px;
}
.page-title {
  margin: 0;
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--color-foreground);
}
.page-subtitle {
  margin: 4px 0 0;
  font-size: 13px;
  color: var(--color-muted-foreground);
}
.page-header-action {
  flex-shrink: 0;
}

/* ===== 继续学习 ===== */
.continue-banner {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
  padding: 14px 16px;
  border: none;
  border-radius: var(--radius-card);
  background: var(--color-accent-soft);
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.15s ease;
}
.continue-banner:hover {
  background: var(--color-accent-soft);
  box-shadow: inset 0 0 0 1px var(--color-accent);
}
.continue-icon {
  width: 22px;
  height: 22px;
  flex-shrink: 0;
  color: var(--color-accent-text);
}
.continue-body {
  display: flex;
  flex: 1;
  min-width: 0;
  flex-direction: column;
  gap: 1px;
}
.continue-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  color: var(--color-accent-text);
}
.continue-title {
  overflow: hidden;
  font-size: 15px;
  font-weight: 600;
  color: var(--color-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.continue-meta {
  overflow: hidden;
  font-size: 12px;
  color: var(--color-muted-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.continue-arrow {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
  color: var(--color-accent-text);
}

/* ===== 工具条 ===== */
.browse-toolbar,
.detail-toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--color-border);
}
.detail-toolbar {
  margin-bottom: 24px;
}
.header-menu-btn {
  display: none;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  color: var(--color-muted-foreground);
  cursor: pointer;
}
.header-menu-btn:hover {
  color: var(--color-foreground);
}

/* ===== 面包屑 ===== */
.learn-breadcrumb {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-wrap: wrap;
  align-items: center;
  gap: 2px;
  font-size: 13px;
}
.crumb {
  padding: 3px 6px;
  border: none;
  border-radius: 6px;
  background: none;
  color: var(--color-muted-foreground);
  font-family: inherit;
  font-size: 13px;
  cursor: pointer;
  transition: color 0.15s ease, background-color 0.15s ease;
}
.crumb:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
.crumb-current,
.crumb-current:hover {
  max-width: 32ch;
  overflow: hidden;
  background: none;
  color: var(--color-foreground);
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
  cursor: default;
}
.crumb-sep {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: var(--color-border-strong);
}

/* ===== 搜索 ===== */
.toolbar-search {
  position: relative;
  width: 220px;
  flex-shrink: 0;
  margin-left: auto;
}
.toolbar-search-icon {
  position: absolute;
  left: 10px;
  top: 50%;
  width: 15px;
  height: 15px;
  margin-top: -7.5px;
  color: var(--color-muted-foreground);
  pointer-events: none;
}
.toolbar-search-input {
  width: 100%;
  height: 32px;
  padding: 0 12px 0 30px;
  border: none;
  border-radius: 7px;
  outline: none;
  background: var(--color-surface-muted);
  color: var(--color-foreground);
  font-size: 13px;
  transition: background-color 0.15s ease, box-shadow 0.15s ease;
}
.toolbar-search-input::placeholder {
  color: var(--color-muted-foreground);
}
.toolbar-search-input::-webkit-search-cancel-button {
  appearance: none;
}
.toolbar-search-input:focus {
  background: var(--color-surface);
  box-shadow: 0 0 0 2px var(--color-accent);
}

/* ===== 详情操作 ===== */
.detail-actions {
  display: flex;
  flex-shrink: 0;
  align-items: center;
  gap: 4px;
  margin-left: auto;
}
.toolbar-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border: none;
  border-radius: var(--radius-card);
  background: none;
  color: var(--color-muted-foreground);
  cursor: pointer;
  transition: color 0.15s ease, background-color 0.15s ease;
}
.toolbar-icon-btn:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}

/* ===== 目录列表：发丝线分隔，不再嵌套卡片 ===== */
.entry-list {
  display: flex;
  flex-direction: column;
}
.entry-row {
  display: flex;
  width: 100%;
  min-height: 52px;
  align-items: center;
  gap: 12px;
  padding: 10px 8px;
  border: none;
  border-bottom: 1px solid var(--color-border);
  background: none;
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.15s ease;
}
.entry-row:hover {
  background: var(--color-surface-muted);
}
.entry-icon {
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  color: var(--color-muted-foreground);
}
.entry-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  font-size: 15px;
  color: var(--color-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.entry-meta {
  flex-shrink: 0;
  font-size: 12px;
  color: var(--color-muted-foreground);
  white-space: nowrap;
}
.entry-arrow {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: var(--color-muted-foreground);
  opacity: 0;
  transition: opacity 0.15s ease;
}
.entry-row:hover .entry-arrow,
.entry-row:focus-visible .entry-arrow {
  opacity: 1;
}

/* ===== 详情页：阅读版心 768px ===== */
.learn-detail-main {
  padding-bottom: 40px;
}
.learn-doc-container {
  max-width: 768px;
  margin: 0 auto;
}
.learn-doc-title {
  margin: 0 0 24px;
  font-size: 30px;
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.25;
  color: var(--color-foreground);
}

/* ===== 移动端遮罩 ===== */
.sidebar-overlay {
  position: fixed;
  inset: 0;
  /* 高于固定页头（z-50）但低于抽屉，否则点页头区域关不掉抽屉 */
  z-index: 55;
  background: rgb(15 23 42 / 0.45);
}

/* ===== 响应式 ===== */
@media (max-width: 1279px) {
  .learn-sidebar-col { width: 240px; }
  .learn-recent-col { width: 240px; }
  .learn-recent-col.is-collapsed { width: 44px; }
}

@media (max-width: 1023px) {
  .header-menu-btn { display: flex; }
  .learn-sidebar-col {
    position: fixed;
    top: 0;
    left: 0;
    z-index: 60;
    width: 280px;
    height: 100vh;
    padding: 12px 10px;
    background: var(--color-surface);
    box-shadow: var(--shadow-overlay);
    transform: translateX(-100%);
    transition: transform 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .learn-sidebar-col.is-open { transform: translateX(0); }
  .learn-doc-container { max-width: 100%; }
}

@media (max-width: 767px) {
  .learn-body { padding-bottom: 24px; }
  .page-header { flex-direction: column; align-items: stretch; }
  .page-header-action { align-self: flex-start; }
  .crumb-current { max-width: 18ch; }
  /* 菜单按钮与搜索同一行，面包屑（若有）另起一行。 */
  .browse-toolbar,
  .detail-toolbar { flex-wrap: wrap; }
  .toolbar-search { order: 2; flex: 1; width: auto; margin-left: 0; }
  .learn-breadcrumb { order: 3; flex-basis: 100%; }
  .detail-actions { order: 3; margin-left: auto; }
  .entry-meta { display: none; }
}

@media (prefers-reduced-motion: reduce) {
  .learn-recent-col,
  .learn-sidebar-col,
  .continue-banner,
  .entry-row,
  .entry-arrow,
  .crumb,
  .toolbar-icon-btn,
  .topbar-icon-btn,
  .toolbar-search-input {
    transition-duration: 0.01ms !important;
  }
}
</style>
