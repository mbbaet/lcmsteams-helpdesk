export default function Home() {
  return (
    <main className="min-h-screen bg-slate-50">
      <section className="bg-[#0F4C81] text-white py-10">
        <div className="max-w-3xl mx-auto text-center px-6">
          <div className="w-24 h-24 bg-white rounded-full mx-auto mb-4 flex items-center justify-center">
            <span className="text-[#0F4C81] font-bold text-xs text-center">
              LC LOGO
            </span>
          </div>

          <h1 className="text-3xl font-bold">
            Laguna College
          </h1>

          <p className="text-blue-100">
            ICT Services Portal
          </p>

          <p className="text-sm text-blue-200 mt-2">
            MS Teams Support Request
          </p>
        </div>
      </section>

      <section className="max-w-3xl mx-auto p-6">

        <div className="bg-white rounded-xl shadow p-6">

          <h2 className="text-xl font-bold text-[#0F4C81] mb-6">
            Identity Verification
          </h2>

          <div className="space-y-4">

            <input
              placeholder="Full Name"
              className="w-full border rounded-lg p-3"
            />

            <select className="w-full border rounded-lg p-3">
              <option>Student</option>
              <option>Faculty</option>
              <option>Administration</option>
            </select>

            <div className="grid md:grid-cols-2 gap-4">

              <input
                placeholder="Student / Employee ID"
                className="border rounded-lg p-3"
              />

              <input
                placeholder="Mobile Number"
                className="border rounded-lg p-3"
              />

            </div>

            <input
              placeholder="Personal Email"
              className="w-full border rounded-lg p-3"
            />

          </div>

        </div>

      </section>
    </main>
  )
}
