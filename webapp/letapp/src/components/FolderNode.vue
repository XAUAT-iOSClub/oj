<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';
import { sortNodesFoldersFirst } from '../utils/treeSort';

interface TreeNode {
  id: string;
  name: string;
  type: 'folder' | 'file';
  path: string;
  children?: TreeNode[];
}

const props = withDefaults(defineProps<{
  node: TreeNode;
  currentPath?: string;
  expandedPaths: Set<string>;
  depth?: number;
}>(), {
  currentPath: '',
  depth: 0,
});

const emit = defineEmits<{
  (e: 'toggle', path: string): void;
  (e: 'select', path: string): void;
  (e: 'browse', path: string): void;
}>();

const PREFIX_RE = /^\d+[-_.\s]+/;
function displayName(name: string): string {
  return name.replace(PREFIX_RE, '');
}

const isFolder = computed(() => props.node.type === 'folder');
const isExpanded = computed(() => props.expandedPaths.has(props.node.path));
const isActive = computed(() => props.currentPath === props.node.path);
const isOnActivePath = computed(() => {
  if (!props.currentPath) return false;
  return props.currentPath.startsWith(props.node.path + '/');
});
const paddingLeft = computed(() => `${10 + props.depth * 16}px`);
const showCount = computed(() => isFolder.value && props.depth === 0);

const childNodes = computed(() => {
  if (!props.node.children) return [];
  return sortNodesFoldersFirst(props.node.children);
});

const cleanName = computed(() => displayName(props.node.name));

function handleFolderClick() {
  emit('toggle', props.node.path);
  emit('browse', props.node.path);
}

function handleClick() {
  if (isFolder.value) {
    handleFolderClick();
  } else {
    emit('select', props.node.path);
  }
}
</script>

<template>
  <div>
    <button
      :class="[
        'fn-node',
        isFolder ? 'fn-folder' : 'fn-file',
        isFolder && props.depth > 0 && 'fn-depth-deep',
        isActive && 'fn-active',
        isOnActivePath && 'fn-on-path',
      ]"
      :style="{ paddingLeft }"
      :aria-expanded="isFolder ? isExpanded : undefined"
      :aria-current="isActive ? 'true' : undefined"
      @click="handleClick"
    >
      <template v-if="isFolder">
        <Icon
          icon="material-symbols:chevron-right-rounded"
          :class="['fn-arrow', isExpanded && 'fn-arrow-open']"
        />
        <Icon :icon="isExpanded ? 'material-symbols:folder-open' : 'material-symbols:folder'" class="fn-icon fn-icon-folder" />
      </template>
      <template v-else>
        <Icon icon="material-symbols:description" class="fn-icon fn-icon-file" />
      </template>
      <span class="fn-name">{{ cleanName }}</span>
      <span v-if="showCount && node.children?.length" class="fn-count">
        {{ node.children.length }}
      </span>
    </button>

    <transition name="fn-expand">
      <div v-if="isFolder && isExpanded" class="fn-children">
        <FolderNode
          v-for="child in childNodes"
          :key="child.id"
          :node="child"
          :current-path="currentPath"
          :expanded-paths="expandedPaths"
          :depth="depth + 1"
          @toggle="(p: string) => emit('toggle', p)"
          @select="(p: string) => emit('select', p)"
          @browse="(p: string) => emit('browse', p)"
        />
      </div>
    </transition>
  </div>
</template>

<style scoped>
.fn-node {
  display: flex;
  align-items: center;
  gap: 6px;
  width: calc(100% - 12px);
  min-height: 32px;
  margin: 1px 6px;
  padding: 5px 8px;
  border: none;
  border-radius: 6px;
  background: none;
  font-family: inherit;
  font-size: 13px;
  line-height: 1.45;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  color: var(--color-muted-foreground);
  transition: background-color 0.15s ease, color 0.15s ease;
}
.fn-node:hover {
  background: var(--color-muted);
}

.fn-folder {
  font-weight: 600;
}
.fn-on-path {
  color: var(--color-foreground);
}

/* 当前项：软色填充 + 强调文字，不再用实心竖条。 */
.fn-active,
.fn-active:hover {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
}

.fn-arrow {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: var(--color-muted-foreground);
  transition: transform 0.16s ease;
}
.fn-arrow-open {
  transform: rotate(90deg);
}
.fn-icon {
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  /* 图标保持单色：警示色只留给真正的警告状态。 */
  color: var(--color-muted-foreground);
}
.fn-active .fn-icon {
  color: var(--color-accent-text);
}

.fn-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.fn-count {
  flex-shrink: 0;
  margin-left: 6px;
  font-size: 11px;
  color: var(--color-muted-foreground);
}

/* 展开动画 */
.fn-expand-enter-active {
  transition: opacity 0.18s ease, transform 0.18s ease;
}
.fn-expand-enter-from {
  opacity: 0;
  transform: translateY(-4px);
}

@media (prefers-reduced-motion: reduce) {
  .fn-node,
  .fn-arrow,
  .fn-expand-enter-active {
    transition-duration: 0.01ms;
  }
  .fn-expand-enter-from {
    transform: none;
  }
}
</style>
