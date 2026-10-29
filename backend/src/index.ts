import Fastify, { type FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  LicenseStatus,
  OrderStatus,
  PlanCode,
  Prisma
} from '@prisma/client';
import { randomBytes } from 'crypto';
import { prisma } from './db.js';

const app = Fastify({ logger: true });
const port = Number(process.env.PORT ?? 8080);
const defaultLimit = Number(process.env.LICENSE_DEVICE_LIMIT ?? 3);
const licensePrefix = (process.env.LICENSE_PREFIX ?? 'BW-PRO').trim();
const afdianWebhookToken = (process.env.AFDIAN_WEBHOOK_TOKEN ?? '').trim();
const autoIssueLicenseOnPaid = (process.env.AUTO_ISSUE_LICENSE_ON_PAID ?? 'true').toLowerCase() !== 'false';
const currentProjectCode = (process.env.PROJECT_CODE ?? 'beauty_wall').trim();
const projectAForwardUrl = (process.env.PROJECT_A_FORWARD_URL ?? '').trim();
const forwardAuthToken = (process.env.FORWARD_AUTH_TOKEN ?? '').trim();
const adminToken = (process.env.ADMIN_API_TOKEN ?? '').trim();

const activateSchema = z.object({
  licenseKey: z.string().min(8),
  deviceId: z.string().min(6),
  deviceName: z.string().optional()
});

const validateSchema = z.object({
  licenseKey: z.string().min(8),
  deviceId: z.string().min(6)
});

const unbindSchema = z.object({
  licenseKey: z.string().min(8),
  deviceId: z.string().min(6)
});

const adminGenerateLicenseSchema = z.object({
  product: z.string().min(1).max(64).optional(),
  maxDevices: z.number().int().min(1).max(20).optional(),
  expiresAt: z.string().datetime().optional()
});

const manualIssueLicenseSchema = z.object({
  force: z.boolean().optional()
});

const adminPlanMappingCreateSchema = z.object({
  planId: z.string().min(8),
  projectCode: z.string().min(1),
  planCode: z.nativeEnum(PlanCode),
  durationDays: z.number().int().positive().nullable().optional(),
  maxDevices: z.number().int().min(1).max(20).optional(),
  isActive: z.boolean().optional(),
  forwardUrl: z.string().url().nullable().optional()
});

const adminPlanMappingUpdateSchema = z.object({
  projectCode: z.string().min(1).optional(),
  planCode: z.nativeEnum(PlanCode).optional(),
  durationDays: z.number().int().positive().nullable().optional(),
  maxDevices: z.number().int().min(1).max(20).optional(),
  isActive: z.boolean().optional(),
  forwardUrl: z.string().url().nullable().optional()
});

const afdianWebhookSchema = z.object({
  orderNo: z.string().optional(),
  out_trade_no: z.string().optional(),
  order_no: z.string().optional(),
  plan_id: z.string().optional(),
  planId: z.string().optional(),
  status: z.union([z.string(), z.number()]).optional(),
  amount: z.union([z.string(), z.number()]).optional(),
  money: z.union([z.string(), z.number()]).optional(),
  currency: z.string().optional(),
  user_id: z.string().optional(),
  plan_title: z.string().optional(),
  data: z.record(z.any()).optional()
}).passthrough();

const defaultPlanMappings: Array<{
  planId: string;
  projectCode: string;
  planCode: PlanCode;
  durationDays: number | null;
}> = [
  { planId: '6eae032a13b411f18cf15254001e7c00', projectCode: 'project_a', planCode: PlanCode.MONTHLY, durationDays: 30 },
  { planId: '6daccb9613b411f1865552540025c377', projectCode: 'project_a', planCode: PlanCode.YEARLY, durationDays: 365 },
  { planId: '6cdd0a6e13b411f18f4152540025c377', projectCode: 'project_a', planCode: PlanCode.LIFETIME, durationDays: null },
  { planId: '8d5707fa16e211f188e552540025c377', projectCode: 'beauty_wall', planCode: PlanCode.MONTHLY, durationDays: 30 },
  { planId: '8c3da67616e211f1974d52540025c377', projectCode: 'beauty_wall', planCode: PlanCode.QUARTERLY, durationDays: 90 },
  { planId: '8baeec1016e211f1825a52540025c377', projectCode: 'beauty_wall', planCode: PlanCode.YEARLY, durationDays: 365 },
  { planId: 'f42818c6177211f195cd52540025c377', projectCode: 'beauty_wall', planCode: PlanCode.LIFETIME, durationDays: null }
];

app.get('/health', async () => ({ ok: true, service: 'license-api', projectCode: currentProjectCode }));

app.post('/seed/dev-license', async () => {
  const key = 'BW-PRO-DEV-0001';
  const existing = await prisma.license.findUnique({ where: { key } });
  if (existing) return { ok: true, key, created: false };

  await prisma.license.create({
    data: {
      key,
      maxDevices: defaultLimit,
      product: 'pro',
      status: LicenseStatus.ACTIVE
    }
  });

  return { ok: true, key, created: true };
});

app.post('/admin/plan-mappings/seed-defaults', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;

  for (const item of defaultPlanMappings) {
    await prisma.planMapping.upsert({
      where: { planId: item.planId },
      create: {
        planId: item.planId,
        projectCode: item.projectCode,
        planCode: item.planCode,
        durationDays: item.durationDays,
        maxDevices: defaultLimit,
        isActive: true,
        forwardUrl: item.projectCode === currentProjectCode ? null : resolveForwardUrl(item.projectCode)
      },
      update: {
        projectCode: item.projectCode,
        planCode: item.planCode,
        durationDays: item.durationDays,
        maxDevices: defaultLimit,
        isActive: true,
        forwardUrl: item.projectCode === currentProjectCode ? null : resolveForwardUrl(item.projectCode)
      }
    });
  }

  return { ok: true, count: defaultPlanMappings.length };
});

app.get('/admin/plan-mappings', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const items = await prisma.planMapping.findMany({ orderBy: [{ projectCode: 'asc' }, { planCode: 'asc' }] });
  return { ok: true, items };
});

app.post('/admin/plan-mappings', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const parsed = adminPlanMappingCreateSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? '参数错误' });
  }

  const created = await prisma.planMapping.create({
    data: {
      planId: parsed.data.planId,
      projectCode: parsed.data.projectCode,
      planCode: parsed.data.planCode,
      durationDays: parsed.data.durationDays ?? null,
      maxDevices: parsed.data.maxDevices ?? defaultLimit,
      isActive: parsed.data.isActive ?? true,
      forwardUrl: parsed.data.forwardUrl ?? null
    }
  });

  return { ok: true, item: created };
});

app.patch('/admin/plan-mappings/:planId', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const params = z.object({ planId: z.string().min(8) }).safeParse(request.params);
  const body = adminPlanMappingUpdateSchema.safeParse(request.body ?? {});
  if (!params.success || !body.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: '参数错误' });
  }

  const updated = await prisma.planMapping.update({
    where: { planId: params.data.planId },
    data: {
      projectCode: body.data.projectCode,
      planCode: body.data.planCode,
      durationDays: body.data.durationDays,
      maxDevices: body.data.maxDevices,
      isActive: body.data.isActive,
      forwardUrl: body.data.forwardUrl
    }
  });

  return { ok: true, item: updated };
});

app.post('/admin/license/generate', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const parsed = adminGenerateLicenseSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? '参数错误' });
  }

  const license = await createLicense({
    product: parsed.data.product ?? 'pro',
    maxDevices: parsed.data.maxDevices ?? defaultLimit,
    expiresAt: parsed.data.expiresAt ? new Date(parsed.data.expiresAt) : null
  });

  return {
    ok: true,
    license: {
      key: license.key,
      product: license.product,
      maxDevices: license.maxDevices,
      expiresAt: license.expiresAt
    }
  };
});

app.post('/activate', async (request, reply) => {
  const parsed = activateSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? '参数错误' });
  }

  const { licenseKey, deviceId, deviceName } = parsed.data;
  const license = await prisma.license.findUnique({
    where: { key: licenseKey },
    include: { activations: true }
  });

  if (!license) return reply.code(404).send({ ok: false, code: 'LICENSE_NOT_FOUND', message: '激活码不存在' });
  if (license.status !== LicenseStatus.ACTIVE) return reply.code(403).send({ ok: false, code: 'LICENSE_NOT_ACTIVE', message: '激活码不可用' });
  if (license.expiresAt && license.expiresAt.getTime() < Date.now()) return reply.code(403).send({ ok: false, code: 'LICENSE_EXPIRED', message: '激活码已过期' });

  const found = license.activations.find(item => item.deviceId === deviceId);
  if (found) {
    const updated = await prisma.activationDevice.update({
      where: { id: found.id },
      data: { lastSeenAt: new Date(), deviceName: deviceName ?? found.deviceName }
    });
    return { ok: true, status: 'already_active', license: { key: license.key, maxDevices: license.maxDevices, usedDevices: license.activations.length }, activation: { deviceId: updated.deviceId } };
  }

  if (license.activations.length >= license.maxDevices) {
    return reply.code(409).send({ ok: false, code: 'DEVICE_LIMIT_EXCEEDED', message: '已达设备上限，请先解绑旧设备', maxDevices: license.maxDevices, usedDevices: license.activations.length });
  }

  const activation = await prisma.activationDevice.create({
    data: {
      licenseId: license.id,
      deviceId,
      deviceName,
      lastSeenAt: new Date()
    }
  });

  return { ok: true, status: 'activated', license: { key: license.key, maxDevices: license.maxDevices, usedDevices: license.activations.length + 1 }, activation: { deviceId: activation.deviceId } };
});

app.post('/webhooks/afdian', async (request, reply) => {
  const parsed = afdianWebhookSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: '回调参数格式错误' });
  }

  if (afdianWebhookToken) {
    const headerToken = readHeaderToken(request.headers);
    const payloadToken = readRecordField(parsed.data, ['token', 'webhookToken']);
    const incomingToken = headerToken || asString(payloadToken);
    if (!incomingToken || incomingToken !== afdianWebhookToken) {
      return reply.code(401).send({ ok: false, code: 'UNAUTHORIZED', message: 'Webhook token 校验失败' });
    }
  }

  const orderPayload = extractAfdianOrderPayload(parsed.data);
  if (!orderPayload.orderNo) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: '缺少订单号' });
  }

  const mapping = orderPayload.planId
    ? await prisma.planMapping.findUnique({ where: { planId: orderPayload.planId } })
    : null;

  const orderStatus = normalizeOrderStatus(orderPayload.statusRaw);
  const amount = normalizeAmountToFen(orderPayload.amountRaw);
  const paidAt = orderStatus === OrderStatus.PAID ? (orderPayload.eventTime ?? new Date()) : null;

  const existingOrder = await prisma.order.findUnique({ where: { orderNo: orderPayload.orderNo } });
  const order = await prisma.order.upsert({
    where: { orderNo: orderPayload.orderNo },
    create: {
      orderNo: orderPayload.orderNo,
      channel: 'afdian',
      amount,
      currency: orderPayload.currency ?? 'CNY',
      status: orderStatus,
      projectCode: mapping?.projectCode,
      planCode: mapping?.planCode,
      planId: orderPayload.planId,
      externalUserId: orderPayload.externalUserId,
      planTitle: orderPayload.planTitle,
      paidAt,
      rawPayload: parsed.data as Prisma.InputJsonValue
    },
    update: {
      amount,
      currency: orderPayload.currency ?? 'CNY',
      status: orderStatus,
      projectCode: mapping?.projectCode ?? existingOrder?.projectCode,
      planCode: mapping?.planCode ?? existingOrder?.planCode,
      planId: orderPayload.planId ?? existingOrder?.planId,
      externalUserId: orderPayload.externalUserId,
      planTitle: orderPayload.planTitle,
      paidAt,
      rawPayload: parsed.data as Prisma.InputJsonValue
    }
  });

  if (!mapping) {
    return {
      ok: true,
      orderNo: order.orderNo,
      status: order.status,
      routed: false,
      message: '未命中 plan_id 映射，已记录订单'
    };
  }

  if (!mapping.isActive) {
    return {
      ok: true,
      orderNo: order.orderNo,
      status: order.status,
      routed: false,
      message: 'plan_id 已停用，已记录订单'
    };
  }

  if (mapping.projectCode !== currentProjectCode) {
    const forwardUrl = mapping.forwardUrl ?? resolveForwardUrl(mapping.projectCode);
    if (!forwardUrl) {
      await prisma.order.update({
        where: { id: order.id },
        data: { forwardError: `NO_FORWARD_URL:${mapping.projectCode}` }
      });
      return reply.code(500).send({ ok: false, code: 'NO_FORWARD_URL', message: `未配置项目 ${mapping.projectCode} 的转发地址` });
    }

    const shouldForward = !(existingOrder?.forwardedAt && existingOrder.status === orderStatus);
    if (!shouldForward) {
      return { ok: true, orderNo: order.orderNo, status: order.status, routed: true, forwarded: false, reason: 'duplicate_status' };
    }

    const forwarded = await forwardToProject(forwardUrl, parsed.data);
    await prisma.order.update({
      where: { id: order.id },
      data: {
        forwardedAt: forwarded.ok ? new Date() : null,
        forwardedTarget: forwardUrl,
        forwardError: forwarded.ok ? null : forwarded.error ?? 'FORWARD_FAILED'
      }
    });

    if (!forwarded.ok) {
      return reply.code(502).send({
        ok: false,
        code: 'FORWARD_FAILED',
        message: forwarded.error ?? '转发失败',
        orderNo: order.orderNo
      });
    }

    return {
      ok: true,
      orderNo: order.orderNo,
      status: order.status,
      routed: true,
      forwarded: true,
      targetProject: mapping.projectCode
    };
  }

  let issuedLicenseKey: string | null = null;
  if (orderStatus === OrderStatus.PAID && autoIssueLicenseOnPaid) {
    const issued = await issueLicenseForOrder(order.orderNo, true);
    issuedLicenseKey = issued?.key ?? null;
  }

  return {
    ok: true,
    orderNo: order.orderNo,
    status: order.status,
    routed: true,
    projectCode: mapping.projectCode,
    autoIssued: Boolean(issuedLicenseKey),
    licenseKey: issuedLicenseKey
  };
});

app.post('/validate', async (request, reply) => {
  const parsed = validateSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? '参数错误' });
  }

  const { licenseKey, deviceId } = parsed.data;
  const license = await prisma.license.findUnique({ where: { key: licenseKey } });
  if (!license) return reply.code(404).send({ ok: false, code: 'LICENSE_NOT_FOUND', message: '激活码不存在' });
  if (license.status !== LicenseStatus.ACTIVE) return reply.code(403).send({ ok: false, code: 'LICENSE_NOT_ACTIVE', message: '激活码不可用' });

  const activation = await prisma.activationDevice.findFirst({ where: { licenseId: license.id, deviceId } });
  if (!activation) return reply.code(403).send({ ok: false, code: 'DEVICE_NOT_ACTIVATED', message: '当前设备未激活' });

  await prisma.activationDevice.update({ where: { id: activation.id }, data: { lastSeenAt: new Date() } });

  return { ok: true, valid: true, license: { key: license.key, maxDevices: license.maxDevices } };
});

app.post('/unbind', async (request, reply) => {
  const parsed = unbindSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: parsed.error.issues[0]?.message ?? '参数错误' });
  }

  const { licenseKey, deviceId } = parsed.data;
  const license = await prisma.license.findUnique({ where: { key: licenseKey } });
  if (!license) return reply.code(404).send({ ok: false, code: 'LICENSE_NOT_FOUND', message: '激活码不存在' });

  const activation = await prisma.activationDevice.findFirst({ where: { licenseId: license.id, deviceId } });
  if (!activation) return reply.code(404).send({ ok: false, code: 'DEVICE_NOT_FOUND', message: '未找到该设备激活记录' });

  await prisma.activationDevice.delete({ where: { id: activation.id } });
  const usedDevices = await prisma.activationDevice.count({ where: { licenseId: license.id } });

  return { ok: true, unbound: true, license: { key: license.key, maxDevices: license.maxDevices, usedDevices } };
});

app.get('/admin/orders', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const query = z.object({ limit: z.coerce.number().int().min(1).max(200).optional() }).safeParse(request.query);
  if (!query.success) return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: 'limit 参数错误' });
  const limit = query.data.limit ?? 50;
  const items = await prisma.order.findMany({
    take: limit,
    orderBy: { createdAt: 'desc' },
    include: { license: true }
  });
  return {
    ok: true,
    items: items.map(order => ({
      orderNo: order.orderNo,
      status: order.status,
      projectCode: order.projectCode,
      planCode: order.planCode,
      planId: order.planId,
      amount: order.amount,
      currency: order.currency,
      paidAt: order.paidAt,
      licenseKey: order.license?.key ?? null,
      forwardedAt: order.forwardedAt,
      forwardedTarget: order.forwardedTarget,
      forwardError: order.forwardError,
      createdAt: order.createdAt
    }))
  };
});

app.get('/admin/licenses', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const query = z.object({ limit: z.coerce.number().int().min(1).max(200).optional() }).safeParse(request.query);
  if (!query.success) return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: 'limit 参数错误' });
  const limit = query.data.limit ?? 50;
  const items = await prisma.license.findMany({
    take: limit,
    orderBy: { createdAt: 'desc' },
    include: { activations: true }
  });
  return {
    ok: true,
    items: items.map(item => ({
      key: item.key,
      status: item.status,
      product: item.product,
      maxDevices: item.maxDevices,
      usedDevices: item.activations.length,
      expiresAt: item.expiresAt,
      createdAt: item.createdAt
    }))
  };
});

app.post('/admin/orders/:orderNo/issue-license', async (request, reply) => {
  if (!ensureAdmin(request, reply)) return;
  const params = z.object({ orderNo: z.string().min(1) }).safeParse(request.params);
  const body = manualIssueLicenseSchema.safeParse(request.body ?? {});
  if (!params.success || !body.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: '参数错误' });
  }

  const order = await prisma.order.findUnique({
    where: { orderNo: params.data.orderNo },
    include: { license: true }
  });
  if (!order) {
    return reply.code(404).send({ ok: false, code: 'ORDER_NOT_FOUND', message: '订单不存在' });
  }
  if (order.license) {
    return { ok: true, orderNo: params.data.orderNo, licenseKey: order.license.key, alreadyIssued: true };
  }
  if (!body.data.force && order.status !== OrderStatus.PAID) {
    return reply.code(409).send({ ok: false, code: 'ORDER_NOT_PAID', message: '订单未支付，无法发码（可使用 force）' });
  }

  const issued = await issueLicenseForOrder(params.data.orderNo, body.data.force ?? false);
  if (!issued) {
    return reply.code(500).send({ ok: false, code: 'ISSUE_FAILED', message: '发码失败，请重试' });
  }

  return { ok: true, orderNo: params.data.orderNo, licenseKey: issued.key };
});

app.get('/license/status', async (request, reply) => {
  const query = z.object({ licenseKey: z.string().min(8) }).safeParse(request.query);
  if (!query.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: 'licenseKey 缺失' });
  }

  const license = await prisma.license.findUnique({
    where: { key: query.data.licenseKey },
    include: { activations: true }
  });

  if (!license) return reply.code(404).send({ ok: false, code: 'LICENSE_NOT_FOUND', message: '激活码不存在' });

  return {
    ok: true,
    license: {
      key: license.key,
      status: license.status,
      maxDevices: license.maxDevices,
      usedDevices: license.activations.length,
      expiresAt: license.expiresAt
    },
    devices: license.activations.map(item => ({
      deviceId: item.deviceId,
      deviceName: item.deviceName,
      lastSeenAt: item.lastSeenAt,
      createdAt: item.createdAt
    }))
  };
});

app.get('/orders/:orderNo', async (request, reply) => {
  const params = z.object({ orderNo: z.string().min(1) }).safeParse(request.params);
  if (!params.success) {
    return reply.code(400).send({ ok: false, code: 'BAD_REQUEST', message: 'orderNo 缺失' });
  }

  const order = await prisma.order.findUnique({
    where: { orderNo: params.data.orderNo },
    include: { license: true }
  });

  if (!order) {
    return reply.code(404).send({ ok: false, code: 'ORDER_NOT_FOUND', message: '订单不存在' });
  }

  return {
    ok: true,
    order: {
      orderNo: order.orderNo,
      channel: order.channel,
      status: order.status,
      amount: order.amount,
      currency: order.currency,
      projectCode: order.projectCode,
      planCode: order.planCode,
      planId: order.planId,
      paidAt: order.paidAt,
      planTitle: order.planTitle,
      externalUserId: order.externalUserId,
      licenseKey: order.license?.key ?? null,
      forwardedAt: order.forwardedAt,
      forwardedTarget: order.forwardedTarget,
      forwardError: order.forwardError
    }
  };
});

async function createLicense(input: {
  product: string;
  maxDevices: number;
  expiresAt: Date | null;
}) {
  const key = await generateUniqueLicenseKey(licensePrefix);
  return prisma.license.create({
    data: {
      key,
      product: input.product,
      maxDevices: input.maxDevices,
      expiresAt: input.expiresAt,
      status: LicenseStatus.ACTIVE
    }
  });
}

async function issueLicenseForOrder(orderNo: string, force: boolean) {
  const order = await prisma.order.findUnique({
    where: { orderNo },
    include: { license: true }
  });
  if (!order) return null;
  if (order.license) return order.license;
  if (!force && order.status !== OrderStatus.PAID) return null;

  const mapping = order.planId
    ? await prisma.planMapping.findUnique({ where: { planId: order.planId } })
    : null;

  const product = resolveProduct(order.planCode, order.planTitle);
  const maxDevices = mapping?.maxDevices ?? defaultLimit;
  const expiresAt = resolveExpiresAt(mapping?.durationDays ?? null, order.paidAt);

  const created = await createLicense({
    product,
    maxDevices,
    expiresAt
  });

  await prisma.order.update({
    where: { id: order.id },
    data: {
      licenseId: created.id
    }
  });

  return created;
}

function resolveProduct(planCode?: PlanCode | null, planTitle?: string | null) {
  if (planCode === PlanCode.LIFETIME) return 'lifetime';
  const normalized = (planTitle ?? '').toLowerCase();
  if (normalized.includes('终身') || normalized.includes('lifetime')) return 'lifetime';
  return 'pro';
}

function resolveExpiresAt(durationDays: number | null, paidAt: Date | null) {
  if (!durationDays) return null;
  const start = paidAt ?? new Date();
  return new Date(start.getTime() + durationDays * 24 * 60 * 60 * 1000);
}

async function generateUniqueLicenseKey(prefix: string) {
  for (let index = 0; index < 8; index += 1) {
    const candidate = `${prefix}-${randomBytes(6).toString('hex').toUpperCase()}`;
    const existing = await prisma.license.findUnique({ where: { key: candidate } });
    if (!existing) return candidate;
  }
  throw new Error('LICENSE_KEY_GENERATE_FAILED');
}

function ensureAdmin(request: FastifyRequest, reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } }) {
  if (!adminToken) return true;
  const header = request.headers['x-admin-token'];
  const token = Array.isArray(header) ? header[0] : header;
  if (token === adminToken) return true;
  reply.code(401).send({ ok: false, code: 'UNAUTHORIZED', message: '管理员鉴权失败' });
  return false;
}

function resolveForwardUrl(projectCode: string) {
  if (projectCode === 'project_a') return projectAForwardUrl || null;
  return null;
}

async function forwardToProject(url: string, payload: Record<string, unknown>) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(forwardAuthToken ? { 'x-forward-token': forwardAuthToken } : {})
      },
      body: JSON.stringify(payload),
      signal: controller.signal
    });
    clearTimeout(timer);
    if (!response.ok) {
      const text = await response.text().catch(() => '');
      return { ok: false, error: `HTTP_${response.status}:${text.slice(0, 160)}` };
    }
    return { ok: true };
  } catch (error) {
    clearTimeout(timer);
    return { ok: false, error: error instanceof Error ? error.message : 'UNKNOWN_FORWARD_ERROR' };
  }
}

function readHeaderToken(headers: Record<string, string | string[] | undefined>) {
  const direct = headers['x-afdian-token'] ?? headers['x-webhook-token'];
  if (Array.isArray(direct)) return direct[0];
  if (typeof direct === 'string' && direct.trim()) return direct.trim();

  const auth = headers.authorization;
  const authValue = Array.isArray(auth) ? auth[0] : auth;
  if (typeof authValue === 'string' && authValue.startsWith('Bearer ')) {
    return authValue.slice('Bearer '.length).trim();
  }
  return null;
}

function extractAfdianOrderPayload(payload: Record<string, unknown>) {
  const data = asRecord(payload.data);
  const orderNo = asString(
    readRecordField(payload, ['orderNo', 'order_no', 'out_trade_no', 'trade_no']) ??
    readRecordField(data, ['orderNo', 'order_no', 'out_trade_no', 'trade_no', 'merchant_order_no'])
  );

  const planId = asString(
    readRecordField(payload, ['plan_id', 'planId']) ??
    readRecordField(data, ['plan_id', 'planId'])
  );

  const statusRaw =
    readRecordField(payload, ['status', 'trade_status', 'order_status']) ??
    readRecordField(data, ['status', 'trade_status', 'order_status']);

  const amountRaw =
    readRecordField(payload, ['amount', 'money', 'total_amount', 'show_amount']) ??
    readRecordField(data, ['amount', 'money', 'total_amount', 'show_amount']);

  const currency = asString(
    readRecordField(payload, ['currency']) ??
    readRecordField(data, ['currency'])
  ) ?? 'CNY';

  const externalUserId = asString(
    readRecordField(payload, ['user_id', 'uid', 'userId']) ??
    readRecordField(data, ['user_id', 'uid', 'userId', 'open_user_id'])
  );

  const planTitle = asString(
    readRecordField(payload, ['plan_title', 'planTitle']) ??
    readRecordField(data, ['plan_title', 'planTitle', 'sku_title', 'title'])
  );

  const eventTimeRaw =
    readRecordField(payload, ['paid_at', 'event_time', 'create_time']) ??
    readRecordField(data, ['paid_at', 'event_time', 'create_time']);

  const eventTime = parseDate(eventTimeRaw);

  return { orderNo, planId, statusRaw, amountRaw, currency, externalUserId, planTitle, eventTime };
}

function normalizeOrderStatus(raw: unknown): OrderStatus {
  if (typeof raw === 'number') {
    if (raw === 1) return OrderStatus.CREATED;
    if (raw === 2) return OrderStatus.PAID;
    if (raw === 3) return OrderStatus.FAILED;
    if (raw === 4) return OrderStatus.REFUNDED;
  }

  const text = String(raw ?? '').trim().toUpperCase();
  if (!text) return OrderStatus.CREATED;
  if (['PAID', 'SUCCESS', 'TRADE_SUCCESS', 'COMPLETED'].includes(text)) return OrderStatus.PAID;
  if (['REFUND', 'REFUNDED'].includes(text)) return OrderStatus.REFUNDED;
  if (['FAIL', 'FAILED', 'CLOSED'].includes(text)) return OrderStatus.FAILED;
  return OrderStatus.CREATED;
}

function normalizeAmountToFen(raw: unknown) {
  if (typeof raw === 'number') {
    if (Number.isInteger(raw)) return Math.max(0, raw);
    return Math.max(0, Math.round(raw * 100));
  }
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (!trimmed) return 0;
    if (trimmed.includes('.')) {
      const amount = Number(trimmed);
      return Number.isFinite(amount) ? Math.max(0, Math.round(amount * 100)) : 0;
    }
    const amount = Number(trimmed);
    return Number.isFinite(amount) ? Math.max(0, Math.round(amount)) : 0;
  }
  return 0;
}

function readRecordField(record: Record<string, unknown> | null, keys: string[]) {
  if (!record) return undefined;
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(record, key)) {
      return record[key];
    }
  }
  return undefined;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function asString(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed ? trimmed : null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return null;
}

function parseDate(value: unknown): Date | null {
  const text = asString(value);
  if (!text) return null;
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) return null;
  return date;
}

const start = async () => {
  try {
    await app.listen({ host: '0.0.0.0', port });
  } catch (error) {
    app.log.error(error);
    process.exit(1);
  }
};

void start();
