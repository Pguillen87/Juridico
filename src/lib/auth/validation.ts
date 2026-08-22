import { z } from 'zod';

export const allowedInviteRoles = [
  'lawyer',
  'operator',
  'reviewer',
  'auditor',
] as const;

export const loginSchema = z.object({
  email: z.string().email('Informe um e-mail válido.'),
  password: z.string().min(1, 'Informe sua senha.'),
});

export const recoverySchema = z.object({
  email: z.string().email('Informe um e-mail válido.'),
});

export const resetPasswordSchema = z
  .object({
    password: z
      .string()
      .min(10, 'A nova senha deve ter pelo menos 10 caracteres.'),
    confirmation: z.string().min(10, 'Confirme a nova senha.'),
  })
  .refine((values) => values.password === values.confirmation, {
    message: 'As senhas precisam ser iguais.',
    path: ['confirmation'],
  });

export const inviteSchema = z.object({
  name: z.string().min(2, 'O nome deve ter pelo menos 2 caracteres.'),
  email: z.string().email('E-mail inválido.'),
  role: z.enum(allowedInviteRoles),
});

export type InviteRole = (typeof allowedInviteRoles)[number];

const userIdSchema = z.string().uuid('Identificador de usuário inválido.');

export const changeRoleSchema = z
  .object({
    userId: userIdSchema,
    role: z.enum(allowedInviteRoles),
  })
  .strict();

export const setActiveSchema = z
  .object({
    userId: userIdSchema,
    isActive: z.boolean(),
  })
  .strict();

export const setOwnerSchema = z
  .object({
    userId: userIdSchema,
    isOwner: z.boolean(),
  })
  .strict();

export const updateOfficeNameSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(2, 'O nome deve ter pelo menos 2 caracteres.')
      .max(160, 'O nome deve ter no máximo 160 caracteres.'),
  })
  .strict();

export const auditFilterSchema = z
  .object({
    action: z.string().trim().min(1).max(80).optional(),
    entityType: z.string().trim().min(1).max(80).optional(),
    limit: z.number().int().min(1).max(100).default(50),
  })
  .strict();
