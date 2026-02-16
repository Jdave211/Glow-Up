"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = Home;
const LooksMaxxingApp_1 = __importDefault(require("@/components/LooksMaxxingApp"));
function Home() {
    return (<main className="min-h-screen bg-slate-50 py-12">
      <div className="container mx-auto px-4">
        <LooksMaxxingApp_1.default />
      </div>
    </main>);
}
