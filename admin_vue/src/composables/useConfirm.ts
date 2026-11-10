import { reactive } from 'vue';

export interface ConfirmOptions {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
}

interface ConfirmState extends ConfirmOptions {
  open: boolean;
}

const state = reactive<ConfirmState>({ open: false, title: '', message: '' });
let resolver: ((value: boolean) => void) | null = null;

/** Substituto do window.confirm: abre o ConfirmDialog e resolve com a escolha. */
export function confirmDialog(options: ConfirmOptions): Promise<boolean> {
  resolver?.(false);
  Object.assign(state, { confirmLabel: 'Confirmar', cancelLabel: 'Cancelar', danger: false }, options, { open: true });
  return new Promise<boolean>((resolve) => {
    resolver = resolve;
  });
}

function settle(value: boolean): void {
  state.open = false;
  resolver?.(value);
  resolver = null;
}

export function useConfirmState() {
  return { state, accept: () => settle(true), cancel: () => settle(false) };
}
