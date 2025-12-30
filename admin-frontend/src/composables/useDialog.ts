import { ElMessageBox, ElMessageBoxData } from 'element-plus'
import type { MessageBoxOptions } from 'element-plus'

/**
 * 对话框 composable
 * 提供统一的确认对话框接口
 */
export function useDialog() {
  /**
   * 确认对话框
   */
  const confirm = (
    message: string,
    title: string = '确认操作',
    options: Partial<MessageBoxOptions> = {}
  ): Promise<ElMessageBoxData> => {
    return ElMessageBox.confirm(message, title, {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning',
      ...options
    })
  }

  /**
   * 警告对话框
   */
  const alert = (
    message: string,
    title: string = '提示',
    type: 'success' | 'warning' | 'info' | 'error' = 'info'
  ): Promise<ElMessageBoxData> => {
    return ElMessageBox.alert(message, title, {
      confirmButtonText: '确定',
      type
    })
  }

  /**
   * 删除确认对话框
   */
  const confirmDelete = (itemName: string = '此项目'): Promise<ElMessageBoxData> => {
    return confirm(
      `删除后数据将无法恢复，确定要删除 ${itemName} 吗？`,
      '确认删除',
      { type: 'error', confirmButtonText: '删除', confirmButtonClass: 'el-button--danger' }
    )
  }

  /**
   * 危险操作确认对话框
   */
  const confirmDanger = (
    message: string,
    title: string = '危险操作'
  ): Promise<ElMessageBoxData> => {
    return confirm(message, title, {
      type: 'error',
      confirmButtonText: '继续执行',
      confirmButtonClass: 'el-button--danger'
    })
  }

  /**
   * 保存确认对话框
   */
  const confirmSave = (): Promise<ElMessageBoxData> => {
    return confirm('是否保存当前的修改？', '保存确认', {
      type: 'info',
      confirmButtonText: '保存'
    })
  }

  /**
   * 输入对话框
   */
  const prompt = (
    message: string,
    title: string = '输入',
    options: Partial<MessageBoxOptions> = {}
  ): Promise<ElMessageBoxData> => {
    return ElMessageBox.prompt(message, title, {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      ...options
    })
  }

  return {
    confirm,
    alert,
    confirmDelete,
    confirmDanger,
    confirmSave,
    prompt
  }
}
