// =============================================================================
//                  SP BOUCHER | SOFTWARE & RESEARCH
//             ARTIFICIAL INTELLIGENCE • FINANCE • ENGINEERING
// =============================================================================
//
// PROJECT METADATA
// -----------------------------------------------------------------------------
// Project          : ORIX Clean
// File             : Scripts/icon.swift
// Description      : Renders the five icon concepts and the final ORIX Clean
//                    icon with Core Graphics (run: swift Scripts/icon.swift
//                    <outdir>).
// Module           : Scripts
// Repository       : https://git.spboucher.ai/orix-clean
// Created          : 2026-11-21
// Last Modified    : 2026-11-21
//
// =============================================================================
// AUTHOR & PROFESSIONAL AFFILIATION
// =============================================================================
//
// Author           : Simon-Pierre Boucher
// Position         : Professor of Finance
// Institution      : Université du Québec en Outaouais (UQO)
// Department       : Département des sciences administratives
// Organization     : SP Boucher
//
// Website          : https://spboucher.ai
// Git              : https://git.spboucher.ai
//
// =============================================================================
// OFFICIAL CONTACT DIRECTORY
// =============================================================================
//
// General          : info@spboucher.ai
// Professional     : contact@spboucher.ai
// Direct           : simon@spboucher.ai
// Research         : research@spboucher.ai
// Development      : dev@spboucher.ai
// Support          : support@spboucher.ai
// Security/Admin   : admin@spboucher.ai
// Notifications    : notifications@spboucher.ai
//
// Preferred Contact: support@spboucher.ai
//
// =============================================================================
// COPYRIGHT & INTELLECTUAL PROPERTY
// =============================================================================
//
// Copyright (c) 2026
// Simon-Pierre Boucher
//
// All rights reserved where applicable.
//
// This file is governed by the applicable project license,
// copyright notices, institutional agreements and relevant law.
//
// Unless expressly authorized by the applicable license or
// rights holder, copying, redistribution, sublicensing,
// publication and commercial exploitation are not permitted.
//
// Existing third-party rights and notices remain unaffected.
//
// =============================================================================
// CONFIDENTIALITY & SECURITY
// =============================================================================
//
// Classification   : Public
// Distribution     : Public repository; use is governed by the project license
// Security Contact : admin@spboucher.ai
//
// Access to this source does not independently grant permission
// to redistribute or disclose confidential materials.
//
// Do not embed credentials, private keys, access tokens,
// certificates or confidential personal information.
//
// =============================================================================
// LICENSE & MAINTENANCE
// =============================================================================
//
// License          : Proprietary, all rights reserved (see license file)
// License File     : LICENSE
// Maintainer       : Simon-Pierre Boucher
// Technical Contact: dev@spboucher.ai
//
// =============================================================================
// END OF SP BOUCHER SOURCE HEADER
// =============================================================================

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/icon"
let S: CGFloat = 1024
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: out + "/" + name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// macOS icon grid: 824 pt rounded square centred on a 1024 canvas, continuous corners, soft drop shadow.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
func platePath() -> CGPath { NSBezierPath(roundedRect: plate, xRadius: 185.4, yRadius: 185.4).cgPath }

func background(_ ctx: CGContext, top: UInt32 = 0x1B2340, bottom: UInt32 = 0x070A16) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(platePath()); ctx.setFillColor(rgb(bottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(platePath()); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft glow behind the mark.
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2DD4BF, 0.28), rgb(0x2DD4BF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 430, options: [])
    // Top inner highlight.
    ctx.addPath(platePath()); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(3); ctx.strokePath()
    ctx.restoreGState()
}

func arc(_ ctx: CGContext, r: CGFloat, w: CGFloat, from: CGFloat, to: CGFloat, colors: [UInt32], cap: CGLineCap = .round, alpha: CGFloat = 1) {
    // Angles in degrees, clockwise from 12 o'clock.
    let c = CGPoint(x: 512, y: 512)
    let a0 = (90 - from) * .pi / 180, a1 = (90 - to) * .pi / 180
    let path = CGMutablePath()
    path.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
    let stroked = path.copy(strokingWithWidth: w, lineCap: cap, lineJoin: .round, miterLimit: 1)
    ctx.saveGState()
    ctx.addPath(stroked); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors.map { rgb($0, alpha) } as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512 - r, y: 512 + r), end: CGPoint(x: 512 + r, y: 512 - r), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func sparkle(_ ctx: CGContext, at p: CGPoint, size: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    let k = size * 0.22
    path.move(to: CGPoint(x: p.x, y: p.y + size))
    path.addQuadCurve(to: CGPoint(x: p.x + size, y: p.y), control: CGPoint(x: p.x + k, y: p.y + k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - size), control: CGPoint(x: p.x + k, y: p.y - k))
    path.addQuadCurve(to: CGPoint(x: p.x - size, y: p.y), control: CGPoint(x: p.x - k, y: p.y - k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + size), control: CGPoint(x: p.x - k, y: p.y + k))
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}

// Concept 1 (chosen): the ORIX "O" as a storage ring. Three quarters hold data as segments of decreasing weight;
// the last quarter has been swept clean and is only a faint track, with a single spark where the sweep ended.
func concept1(_ ctx: CGContext) {
    background(ctx)
    arc(ctx, r: 250, w: 20, from: 0, to: 360, colors: [0xFFFFFF, 0xFFFFFF], cap: .butt, alpha: 0.07)
    arc(ctx, r: 250, w: 118, from: 14, to: 112, colors: [0x5EEAD4, 0x14B8A6])
    arc(ctx, r: 250, w: 118, from: 142, to: 206, colors: [0x22D3EE, 0x0891B2])
    arc(ctx, r: 250, w: 118, from: 236, to: 268, colors: [0x818CF8, 0x5B5BF0])
    // The swept quarter: a thin bright trail fading out.
    for i in 0 ..< 10 {
        let a = 290 + CGFloat(i) * 6.2
        arc(ctx, r: 250, w: 20, from: a, to: a + 3.4, colors: [0xCCFBF1, 0xCCFBF1], cap: .round, alpha: 0.16 + CGFloat(i) * 0.075)
    }
    let tip = CGFloat(-6.0 * Double.pi / 180.0)
    sparkle(ctx, at: CGPoint(x: 512 + 250 * sin(tip), y: 512 + 250 * cos(tip)), size: 62, color: rgb(0xFFFFFF))
    sparkle(ctx, at: CGPoint(x: 512, y: 512), size: 30, color: rgb(0x5EEAD4, 0.9))
}

// Concept 2: geometric treemap.
func concept2(_ ctx: CGContext) {
    background(ctx)
    let rects: [(CGRect, UInt32)] = [(CGRect(x: 250, y: 430, width: 300, height: 344), 0x14B8A6), (CGRect(x: 574, y: 560, width: 200, height: 214), 0x0891B2),
                                     (CGRect(x: 574, y: 430, width: 200, height: 106), 0x5B5BF0), (CGRect(x: 250, y: 250, width: 170, height: 156), 0x6366F1),
                                     (CGRect(x: 444, y: 250, width: 150, height: 156), 0x22D3EE)]
    for (r, c) in rects { ctx.addPath(CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.setFillColor(rgb(c)); ctx.fillPath() }
    ctx.addPath(CGPath(roundedRect: CGRect(x: 618, y: 250, width: 156, height: 156), cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setStrokeColor(rgb(0xCCFBF1, 0.5)); ctx.setLineWidth(8); ctx.setLineDash(phase: 0, lengths: [22, 16]); ctx.strokePath()
    sparkle(ctx, at: CGPoint(x: 696, y: 328), size: 46, color: rgb(0xFFFFFF))
}

// Concept 3: minimal disk with a cleared sector.
func concept3(_ ctx: CGContext) {
    background(ctx)
    ctx.setFillColor(rgb(0x0891B2)); ctx.fillEllipse(in: CGRect(x: 232, y: 232, width: 560, height: 560))
    ctx.move(to: CGPoint(x: 512, y: 512)); ctx.addArc(center: CGPoint(x: 512, y: 512), radius: 280, startAngle: .pi / 2, endAngle: .pi * 0.05, clockwise: true)
    ctx.closePath(); ctx.setFillColor(rgb(0x0B1020)); ctx.fillPath()
    ctx.setFillColor(rgb(0x0B1020)); ctx.fillEllipse(in: CGRect(x: 442, y: 442, width: 140, height: 140))
    ctx.setStrokeColor(rgb(0x5EEAD4)); ctx.setLineWidth(18); ctx.strokeEllipse(in: CGRect(x: 232, y: 232, width: 560, height: 560))
}

// Concept 4: layered storage sheets.
func concept4(_ ctx: CGContext) {
    background(ctx)
    for (i, c) in [0x5B5BF0, 0x0891B2, 0x14B8A6].enumerated() {
        let y = 300 + CGFloat(i) * 130
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 512, y: y + 150)); p.addLine(to: CGPoint(x: 800, y: y + 40)); p.addLine(to: CGPoint(x: 512, y: y - 70)); p.addLine(to: CGPoint(x: 224, y: y + 40)); p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(rgb(UInt32(c), i == 2 ? 1 : 0.75)); ctx.fillPath()
    }
    sparkle(ctx, at: CGPoint(x: 512, y: 600), size: 50, color: rgb(0xFFFFFF))
}

// Concept 5: ORIX monogram ring with a clean notch.
func concept5(_ ctx: CGContext) {
    background(ctx)
    arc(ctx, r: 240, w: 130, from: 40, to: 360, colors: [0x5EEAD4, 0x5B5BF0], cap: .butt)
    ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: 592, y: 700, width: 70, height: 70))
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let concepts: [(String, (CGContext) -> Void)] = [("concept-1-storage-ring-sweep", concept1), ("concept-2-treemap", concept2), ("concept-3-disk-sector", concept3),
                                                 ("concept-4-layers", concept4), ("concept-5-monogram-notch", concept5)]
for (name, draw) in concepts { save(canvas(draw), name + ".png") }
save(canvas(concept1), "ORIXClean-1024.png")
print("icons written to \(out)")
