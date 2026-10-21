-- O relatório de localização (beacon) do app agora pode ocorrer fora de um
-- canal (sempre ativo). Ainda referencia o canal quando o usuário sentou, mas
-- não é mais obrigatório.
ALTER TABLE locations ALTER COLUMN channel_id DROP NOT NULL;