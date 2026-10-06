<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { Icon } from '@iconify/vue';
import FolderNode from './FolderNode.vue';
import { sortNodesFoldersFirst } from '../utils/treeSort';

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

interface HeadingItem {
  level: number;
  text: string;
  id: string;
}

const props = defineProps<{
  tree: TreeNode[];
  currentPath?: string;
  headings?: HeadingItem[];
  /** 正文里当前滚动到的小节 id，用于高亮目录项。 */
  activeHeading?: string;
  searchQuery?: string;
}>();

const emit = defineEmits<{
  (e: 'select', path: string): void;
  (e: 'heading', id: string): void;
  (e: 'browse', path: string): void;
  (e: 'rescan'): void;
}>();

/** ====== 状态 ====== */
const activeTab = ref<'files' | 'headings'>('files');
const localSearch = ref('');
const effectiveSearch = computed(() => props.searchQuery || localSearch.value);
const expandedPaths = ref<Set<string>>(new Set());
const STORAGE_KEY = 'learn_sidebar_expanded';

/** ====== 递归：搜索过滤 ====== */
function filterTree(nodes: TreeNode[], q: string): TreeNode[] {
  if (!q) return sortNodesFoldersFirst(nodes);
  const lower = q.toLowerCase();
  const result: TreeNode[] = [];
  for (const node of nodes) {
    if (node.type === 'folder') {
      const filtered = filterTree(node.children || [], q);
      if (filtered.length > 0 || node.name.toLowerCase().includes(lower)) {
        result.push({ ...node, children: filtered });
      }
    } else if (node.name.toLowerCase().includes(lower)) {
      result.push(node);
    }
  }
  return sortNodesFoldersFirst(result);
}

const displayTree = computed(() => filterTree(props.tree, effectiveSearch.value));

/** ====== 自动展开当前路径的所有父级 ====== */
function expandAncestors(path: string) {
  const parts = path.split('/');
  const next = new Set(expandedPaths.value);
  let accumulated = '';
  for (let i = 0; i < parts.length - 1; i++) {
    const part = parts[i] || '';
    accumulated = accumulated ? accumulated + '/' + part : part;
    next.add(accumulated);
  }
  expandedPaths.value = next;
}

onMounted(() => {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) expandedPaths.value = new Set(JSON.parse(saved));
  } catch { /* ignore */ }
  if (props.currentPath) expandAncestors(props.currentPath);
});

watch(() => props.currentPath, (p) => {
  if (p) {
    expandAncestors(p);
    nextTick(() => {
      const el = document.querySelector('.fn-active');
      if (el) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    });
  }
});

watch(expandedPaths, (val) => {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify([...val])); } catch { /* ignore */ }
}, { deep: true });

function toggleExpand(path: string) {
  const next = new Set(expandedPaths.value);
  if (next.has(path)) next.delete(path); else next.add(path);
  expandedPaths.value = next;
}
</script>

<template>
  <div class="learn-sidebar">
    <!-- 搜索框 -->
    <div class="sidebar-search">
      <Icon icon="material-symbols:search-rounded" class="search-icon" aria-hidden="true" />
      <label class="sr-only" for="learn-sidebar-search">搜索学习资料</label>
      <input
        id="learn-sidebar-search"
        v-model="localSearch"
        type="search"
        placeholder="搜索资料"
        class="search-input"
      />
      <button
        v-if="localSearch"
        type="button"
        class="search-clear"
        aria-label="清空搜索"
        @click="localSearch = ''"
      >
        <Icon icon="material-symbols:close-rounded" class="h-3.5 w-3.5" aria-hidden="true" />
      </button>
    </div>

    <!-- Tab 切换 -->
    <div class="sidebar-tabs">
      <div class="ui-segmented ui-segmented-fill" role="group" aria-label="侧栏视图">
        <button
          type="button"
          class="ui-segmented-item"
          :class="{ 'is-active': activeTab === 'files' }"
          :aria-pressed="activeTab === 'files'"
          @click="activeTab = 'files'"
        >
          资料目录
        </button>
        <button
          type="button"
          class="ui-segmented-item"
          :class="{ 'is-active': activeTab === 'headings' }"
          :aria-pressed="activeTab === 'headings'"
          @click="activeTab = 'headings'"
        >
          本文目录
        </button>
      </div>
      <button
        v-if="activeTab === 'files'"
        type="button"
        class="tab-icon-btn"
        aria-label="重新扫描目录"
        @click="emit('rescan')"
      >
        <Icon icon="material-symbols:refresh" class="h-4 w-4" aria-hidden="true" />
      </button>
    </div>

    <!-- 文件树 -->
    <div v-show="activeTab === 'files'" class="tree-content">
      <div v-if="displayTree.length === 0" class="tree-empty">
        <Icon icon="material-symbols:folder-off" class="empty-icon" aria-hidden="true" />
        <p class="empty-text">{{ effectiveSearch ? '无匹配结果' : '暂无学习资料' }}</p>
      </div>
      <template v-else>
        <FolderNode
          v-for="node in displayTree"
          :key="node.id"
          :node="node"
          :current-path="currentPath || ''"
          :expanded-paths="expandedPaths"
          :depth="0"
          @toggle="toggleExpand"
          @select="(p: string) => emit('select', p)"
          @browse="(p: string) => emit('browse', p)"
        />
      </template>
    </div>

    <!-- 本文目录 -->
    <div v-show="activeTab === 'headings'" class="tree-content">
      <div v-if="!headings || headings.length === 0" class="tree-empty">
        <Icon icon="material-symbols:text-snippet" class="empty-icon" aria-hidden="true" />
        <p class="empty-text">无标题结构</p>
      </div>
      <nav v-else class="heading-nav" aria-label="本文目录">
        <button
          v-for="h in headings"
          :key="h.id"
          type="button"
          :class="[
            'heading-item',
            `heading-level-${h.level}`,
            h.id === activeHeading && 'is-active',
          ]"
          :aria-current="h.id === activeHeading ? 'true' : undefined"
          @click="emit('heading', h.id)"
        >
          {{ h.text }}
        </button>
      </nav>
    </div>
  </div>
</template>

<style scoped>
.learn-sidebar {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

/* ---------- 搜索：无边框填充式，贴近 macOS 搜索框 ---------- */
.sidebar-search {
  position: relative;
  flex-shrink: 0;
  padding: 4px 10px 10px;
}
.search-icon {
  position: absolute;
  left: 20px;
  top: 20px;
  width: 15px;
  height: 15px;
  margin-top: -7.5px;
  color: var(--color-muted-foreground);
  pointer-events: none;
}
.search-input {
  width: 100%;
  height: 32px;
  padding: 0 30px 0 30px;
  border: none;
  border-radius: 7px;
  background: var(--color-surface-muted);
  color: var(--color-foreground);
  font-size: 13px;
  outline: none;
  transition: background-color 0.15s ease, box-shadow 0.15s ease;
}
.search-input::placeholder {
  color: var(--color-muted-foreground);
}
.search-input::-webkit-search-cancel-button {
  appearance: none;
}
.search-input:focus {
  background: var(--color-surface);
  box-shadow: 0 0 0 2px var(--color-accent);
}
.search-clear {
  position: absolute;
  right: 18px;
  top: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-top: -7.5px;
  padding: 2px;
  border: none;
  background: none;
  color: var(--color-muted-foreground);
  cursor: pointer;
}
.search-clear:hover {
  color: var(--color-foreground);
}

/* ---------- 视图切换 ---------- */
.sidebar-tabs {
  display: flex;
  flex-shrink: 0;
  align-items: center;
  gap: 6px;
  padding: 0 10px 10px;
}
.sidebar-tabs .ui-segmented-item {
  min-height: 30px;
  padding-inline: 8px;
  font-size: 12.5px;
}
/* 分段控件的 44px 触控规格来自设计系统，这里只收紧字号的默认值，不覆盖触屏。 */
@media (pointer: coarse) {
  .sidebar-tabs .ui-segmented-item {
    min-height: 44px;
  }
}
.tab-icon-btn {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border: none;
  border-radius: 7px;
  background: none;
  color: var(--color-muted-foreground);
  cursor: pointer;
  transition: color 0.15s ease, background-color 0.15s ease;
}
.tab-icon-btn:hover {
  color: var(--color-foreground);
  background: var(--color-muted);
}

/* ---------- 内容区：只有这里滚动，搜索与切换常驻 ---------- */
.tree-content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 2px 0 12px;
  scrollbar-width: thin;
  scrollbar-color: var(--color-border) transparent;
}
.tree-content::-webkit-scrollbar {
  width: 10px;
}
.tree-content::-webkit-scrollbar-track {
  background: transparent;
}
.tree-content::-webkit-scrollbar-thumb {
  border: 3px solid transparent;
  border-radius: 5px;
  background-color: var(--color-border);
  background-clip: content-box;
}
.tree-content::-webkit-scrollbar-thumb:hover {
  background-color: var(--color-muted-foreground);
  background-clip: content-box;
}

.tree-empty {
  padding: 32px 16px;
  text-align: center;
}
.empty-icon {
  width: 28px;
  height: 28px;
  margin-bottom: 8px;
  color: var(--color-border-strong);
}
.empty-text {
  margin: 0;
  font-size: 12px;
  color: var(--color-muted-foreground);
}

/* ---------- 本文目录 ---------- */
.heading-nav {
  display: flex;
  flex-direction: column;
  gap: 1px;
  padding: 0 8px;
}
.heading-item {
  display: block;
  width: 100%;
  overflow: hidden;
  padding: 6px 8px;
  border: none;
  border-radius: 6px;
  background: none;
  color: var(--color-muted-foreground);
  font-family: inherit;
  font-size: 13px;
  text-align: left;
  text-overflow: ellipsis;
  white-space: nowrap;
  cursor: pointer;
  transition: background-color 0.15s ease, color 0.15s ease;
}
.heading-item:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
.heading-item.is-active,
.heading-item.is-active:hover {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
}
.heading-level-1 {
  font-weight: 600;
}
.heading-level-2 {
  padding-left: 20px;
}
.heading-level-3 {
  padding-left: 32px;
  font-size: 12.5px;
}
/* 语料里 h4 不少（约 120 个），必须继续缩进，否则会比 h3 还靠左。 */
.heading-level-4 {
  padding-left: 44px;
  font-size: 12.5px;
}
.heading-level-5 {
  padding-left: 56px;
  font-size: 12.5px;
}
.heading-level-6 {
  padding-left: 68px;
  font-size: 12.5px;
}

@media (prefers-reduced-motion: reduce) {
  .search-input,
  .tab-icon-btn,
  .heading-item {
    transition-duration: 0.01ms;
  }
}
</style>
