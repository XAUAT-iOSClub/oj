<script setup lang="ts">
import { computed } from 'vue';
import { Icon } from '@iconify/vue';

interface TreeNode {
  id: string;
  name: string;
  type: 'folder' | 'file';
  path: string;
  children?: TreeNode[];
}

const props = defineProps<{
  node: TreeNode;
}>();

const emit = defineEmits<{
  (e: 'open', path: string): void;
}>();

const PREFIX_RE = /^\d+[-_.\s]+/;
function displayName(name: string): string {
  return name.replace(PREFIX_RE, '');
}

function countFiles(node: TreeNode): number {
  if (node.type === 'file') return 1;
  if (!node.children) return 0;
  return node.children.reduce((sum, c) => sum + countFiles(c), 0);
}

const isFile = computed(() => props.node.type === 'file');
const fileCount = computed(() => countFiles(props.node));
const cleanName = computed(() => displayName(props.node.name));
const sortedChildren = computed(() => {
  if (!props.node.children) return [];
  return [...props.node.children].sort((a, b) => {
    if (a.type === 'folder' && b.type !== 'folder') return -1;
    if (a.type !== 'folder' && b.type === 'folder') return 1;
    return a.name.localeCompare(b.name, 'zh-CN');
  });
});

function handleClick() {
  if (isFile.value) {
    emit('open', props.node.path);
  }
}
</script>

<template>
  <div v-if="isFile" class="preview-file" @click="handleClick">
    <Icon icon="material-symbols:description" class="preview-file-icon" />
    <span class="preview-file-name">{{ cleanName }}</span>
  </div>
  <div v-else class="preview-folder">
    <div class="preview-folder-header">
      <Icon icon="material-symbols:folder" class="preview-folder-icon" />
      <span class="preview-folder-name">{{ cleanName }}</span>
      <span class="preview-folder-count">{{ fileCount }} 篇</span>
    </div>
    <div class="preview-folder-children">
      <FolderPreview
        v-for="child in sortedChildren"
        :key="child.id"
        :node="child"
        @open="(p: string) => emit('open', p)"
      />
    </div>
  </div>
</template>

<style scoped>
.preview-folder {
  margin-bottom: 16px;
  border: 1px solid var(--color-border);
  border-radius: 10px;
  background: var(--color-surface);
  overflow: hidden;
}
:global(html.dark) .preview-folder {
  border-color: var(--color-border);
  background: var(--color-surface-muted);
}
.preview-folder-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 14px 16px;
  background: var(--color-surface-muted);
  border-bottom: 1px solid var(--color-border);
}
:global(html.dark) .preview-folder-header {
  background: var(--color-background);
  border-bottom-color: var(--color-border);
}
.preview-folder-icon {
  width: 20px;
  height: 20px;
  color: var(--color-warning-text);
  flex-shrink: 0;
}
.preview-folder-name {
  font-size: 14px;
  font-weight: 700;
  color: var(--color-foreground);
  flex: 1;
}
:global(html.dark) .preview-folder-name {
  color: var(--color-foreground);
}
.preview-folder-count {
  font-size: 12px;
  color: var(--color-muted-foreground);
}
.preview-folder-children {
  padding: 8px 16px;
}
.preview-file {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.12s;
}
.preview-file:hover {
  background: var(--color-accent-soft);
}
:global(html.dark) .preview-file:hover {
  background: var(--color-accent-soft);
}
.preview-file-icon {
  width: 16px;
  height: 16px;
  color: var(--color-accent-text);
  flex-shrink: 0;
}
:global(html.dark) .preview-file-icon {
  color: var(--color-accent-text);
}
.preview-file-name {
  font-size: 13px;
  color: var(--color-muted-foreground);
}
:global(html.dark) .preview-file-name {
  color: var(--color-foreground);
}
</style>
