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

/** ====== 递归：文件夹优先 + 自然（数值）排序 ====== */
function sortNodes(nodes: TreeNode[]): TreeNode[] {
  return sortNodesFoldersFirst(nodes);
}

/** ====== 递归：搜索过滤 ====== */
function filterTree(nodes: TreeNode[], q: string): TreeNode[] {
  if (!q) return sortNodes(nodes);
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
  return sortNodes(result);
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
      const el = document.querySelector('.tree-node-active');
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

function handleSelect(path: string) {
  emit('select', path);
}

function handleBrowse(path: string) {
  emit('browse', path);
}
</script>

<template>
  <div class="learn-sidebar">
    <!-- 搜索框 -->
    <div class="sidebar-search">
      <Icon icon="material-symbols:search" class="search-icon" />
      <input
        v-model="localSearch"
        type="text"
        placeholder="搜索资料…"
        class="search-input"
      />
      <button v-if="localSearch" class="search-clear" @click="localSearch = ''">
        <Icon icon="material-symbols:close" class="h-3 w-3" />
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
        class="tab-rescan"
        aria-label="重新扫描目录"
        @click="emit('rescan')"
      >
        <Icon icon="material-symbols:refresh" class="h-4 w-4" aria-hidden="true" />
      </button>
    </div>

    <!-- 文件树 -->
    <div v-show="activeTab === 'files'" class="tree-content">
      <div v-if="displayTree.length === 0" class="tree-empty">
        <Icon icon="material-symbols:folder-off" class="empty-icon" />
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
          @select="handleSelect"
          @browse="handleBrowse"
        />
      </template>
    </div>

    <!-- 本文目录 -->
    <div v-show="activeTab === 'headings'" class="tree-content">
      <div v-if="!headings || headings.length === 0" class="tree-empty">
        <Icon icon="material-symbols:text-snippet" class="empty-icon" />
        <p class="empty-text">无标题结构</p>
      </div>
      <div v-else>
        <button
          v-for="(h, i) in headings"
          :key="i"
          :class="['heading-item', `heading-level-${h.level}`]"
          @click="emit('heading', h.id)"
        >
          <span class="heading-text">{{ h.text }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.learn-sidebar {
  width: 280px;
  min-width: 280px;
  height: 100vh;
  position: sticky;
  top: 76px;
  background: var(--color-surface);
  border-right: 1px solid var(--color-border);
  display: flex;
  flex-direction: column;
  z-index: 20;
  overflow: hidden;
}
:global(html.dark) .learn-sidebar {
  background: var(--color-surface);
  border-right-color: var(--color-border);
}

.sidebar-search {
  padding: 12px 12px 0;
  position: relative;
}
.search-icon {
  position: absolute; left: 24px; top: 30px; transform: translateY(-50%);
  color: var(--color-muted-foreground); width: 16px; height: 16px;
}
.search-input {
  width: 100%; height: 38px; padding: 0 32px;
  border: 1px solid var(--color-border); border-radius: 8px; font-size: 14px;
  outline: none; background: var(--color-surface-muted); color: var(--color-foreground); transition: border-color 0.2s, box-shadow 0.2s;
}
.search-input:focus {
  border-color: var(--color-accent);
  box-shadow: 0 0 0 3px rgb(14 165 183 / 0.12);
}
.search-input::placeholder { color: var(--color-muted-foreground); }
:global(html.dark) .search-input {
  background: var(--color-surface-muted); border-color: var(--color-border-strong); color: var(--color-foreground);
}
.search-clear {
  position: absolute; right: 24px; top: 30px; transform: translateY(-50%);
  background: none; border: none; cursor: pointer; color: var(--color-muted-foreground); padding: 2px;
}
.search-clear:hover { color: var(--color-muted-foreground); }

.sidebar-tabs {
  display: flex; align-items: center; padding: 12px; gap: 8px;
  border-bottom: 1px solid var(--color-border);
}
:global(html.dark) .sidebar-tabs { border-bottom-color: var(--color-border); }
/* 分段控件样式来自全局 .ui-segmented */
.tab-rescan {
  display: inline-flex; width: 40px; height: 40px; flex-shrink: 0;
  align-items: center; justify-content: center;
  border: none; background: none; cursor: pointer;
  color: var(--color-muted-foreground); border-radius: 8px; transition: color 0.18s, background-color 0.18s;
}
.tab-rescan:hover { color: var(--color-accent-text); background: var(--color-accent-soft); }

.tree-content {
  flex: 1; overflow-y: auto; padding: 8px 0;
}
.tree-content::-webkit-scrollbar { width: 4px; }
.tree-content::-webkit-scrollbar-thumb { background: var(--color-muted); border-radius: 2px; }
:global(html.dark) .tree-content::-webkit-scrollbar-thumb { background: var(--color-muted); }

.tree-empty { padding: 32px 16px; text-align: center; }
.empty-icon { width: 32px; height: 32px; color: var(--color-foreground); margin-bottom: 8px; }
:global(html.dark) .empty-icon { color: var(--color-muted-foreground); }
.empty-text { font-size: 12px; color: var(--color-muted-foreground); margin: 0; }

.heading-item {
  display: block; width: 100%; text-align: left; border: none; background: none;
  cursor: pointer; font-size: 13px; color: var(--color-muted-foreground); padding: 5px 12px;
  transition: background 0.12s, color 0.12s; white-space: nowrap;
  overflow: hidden; text-overflow: ellipsis; font-family: inherit;
}
.heading-item:hover { background: var(--color-muted); color: var(--color-accent-text); }
:global(html.dark) .heading-item { color: var(--color-foreground); }
:global(html.dark) .heading-item:hover { background: var(--color-surface-muted); color: var(--color-accent-text); }
.heading-level-1 { padding-left: 12px; font-weight: 600; }
.heading-level-2 { padding-left: 24px; }
.heading-level-3 { padding-left: 36px; font-size: 12px; }
</style>
