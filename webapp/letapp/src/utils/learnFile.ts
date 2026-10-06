// 学习资料的文件类型判断。侧栏、目录列表与"最近浏览"共用同一套规则，
// 避免各处各写一份扩展名数组而慢慢走样。

const IMAGE_EXTENSIONS = ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp'];
const CODE_EXTENSIONS = [
  'js', 'ts', 'py', 'c', 'cpp', 'h', 'java', 'go', 'rs', 'json', 'html', 'css',
];

function extensionOf(name: string): string {
  return name.split('.').pop()?.toLowerCase() || '';
}

/** 文件类型对应的图标名。 */
export function fileIcon(name: string): string {
  const ext = extensionOf(name);
  if (IMAGE_EXTENSIONS.includes(ext)) return 'material-symbols:image-outline';
  if (ext === 'pdf') return 'material-symbols:picture-as-pdf-outline';
  if (CODE_EXTENSIONS.includes(ext)) return 'material-symbols:code';
  return 'material-symbols:description';
}

/** 文件类型的中文标签，用于行尾的次要信息。 */
export function fileTypeLabel(name: string): string {
  const ext = extensionOf(name);
  if (ext === 'md') return 'Markdown';
  if (ext === 'pdf') return 'PDF';
  if (IMAGE_EXTENSIONS.includes(ext)) return '图片';
  if (CODE_EXTENSIONS.includes(ext)) return '代码';
  return '文档';
}
