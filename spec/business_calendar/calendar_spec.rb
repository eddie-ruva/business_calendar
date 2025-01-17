# frozen_string_literal: true

require "business/calendar"
require "time"

RSpec.configure do |config|
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

RSpec.describe BusinessCalendar::Calendar do
  describe ".load" do
    subject(:load_calendar) { described_class.load(calendar) }

    let(:dummy_calendar) { { "working_days" => ["monday"] } }
    let(:fixture_path) { File.join(File.dirname(__FILE__), "../fixtures", "calendars") }

    before do
      described_class.load_paths = [fixture_path, { "foobar" => dummy_calendar }]
    end

    context "when given a calendar from a custom directory" do
      let(:calendar) { "ecb" }

      after { described_class.load_paths = nil }

      it "loads the yaml file" do
        path = Pathname.new(fixture_path).join("ecb.yml")
        expect(YAML).to receive(:safe_load).
          with(path.read, permitted_classes: [Date]).
          and_return({})

        load_calendar
      end

      it { is_expected.to be_a described_class }

      context "that also exists as a default calendar" do
        let(:calendar) { "bacs" }

        it "uses the custom calendar" do
          expect(load_calendar.business_day?(Date.parse("25th December 2014"))).
            to eq(true)
        end
      end
    end

    context "when loading a calendar as a hash" do
      let(:calendar) { "foobar" }

      it { is_expected.to be_a described_class }
    end

    context "when given a calendar that does not exist" do
      let(:calendar) { "invalid-calendar" }

      specify { expect { load_calendar }.to raise_error(/No such calendar/) }
    end

    context "when given a calendar that has invalid keys" do
      let(:calendar) { "invalid-keys" }

      specify do
        expect { load_calendar }.
          to raise_error(
            "Only valid keys are: holidays, working_days, extra_working_dates",
          )
      end
    end

    context "when given real business data" do
      let(:data_path) do
        File.join(File.dirname(__FILE__), "..", "lib", "business", "data")
      end

      it "validates they are all loadable by the calendar" do
        Dir.glob("#{data_path}/*").each do |filename|
          calendar_name = File.basename(filename, ".yml")
          calendar = described_class.load(calendar_name)

          expect(calendar.working_days.length).to be >= 1
        end
      end
    end
  end

  describe ".new" do
    it "allows to skip a name" do
      instance = described_class.new
      expect(instance.name).to eq nil
    end

    it "allows to set a name" do
      instance = described_class.new(name: "foo")
      expect(instance.name).to eq "foo"
    end
  end

  describe "#set_working_days" do
    subject(:set_working_days) { calendar.set_working_days(working_days) }

    let(:calendar) { described_class.new(name: "test") }
    let(:working_days) { [] }

    context "when given valid working days" do
      let(:working_days) { %w[mon fri] }

      before { set_working_days }

      it "assigns them" do
        expect(calendar.working_days).to eq(working_days)
      end

      context "that are unnormalised" do
        let(:working_days) { %w[Monday Friday] }

        it "normalises them" do
          expect(calendar.working_days).to eq(%w[mon fri])
        end
      end
    end

    context "when given an invalid business day" do
      let(:working_days) { %w[Notaday] }

      specify { expect { set_working_days }.to raise_error(/Invalid day/) }
    end

    context "when given nil" do
      let(:working_days) { nil }

      it "uses the default business days" do
        expect(calendar.working_days).to eq(calendar.default_working_days)
      end
    end
  end

  describe "#set_holidays" do
    subject(:holidays) { calendar.holidays }

    let(:calendar) { described_class.new(name: "test") }
    let(:holiday_dates) { [] }

    before { calendar.set_holidays(holiday_dates) }

    context "when given valid business days" do
      let(:holiday_dates) { ["1st Jan, 2013"] }

      it { is_expected.to_not be_empty }

      it "converts them to Date objects" do
        expect(holidays).to all be_a Date
      end
    end

    context "when given nil" do
      let(:holiday_dates) { nil }

      it { is_expected.to be_empty }
    end
  end

  describe "#set_extra_working_dates" do
    subject(:extra_working_dates) { calendar.extra_working_dates }

    let(:calendar) { described_class.new(name: "test") }
    let(:extra_dates) { [] }

    before { calendar.set_extra_working_dates(extra_dates) }

    context "when given valid business days" do
      let(:extra_dates) { ["1st Jan, 2013"] }

      it { is_expected.to_not be_empty }

      it "converts them to Date objects" do
        expect(extra_working_dates).to all be_a Date
      end
    end

    context "when given nil" do
      let(:holidays) { nil }

      it { is_expected.to be_empty }
    end
  end

  context "when holiday is also a working date" do
    let(:instance) do
      described_class.new(name: "test",
                          holidays: ["2018-01-06"],
                          extra_working_dates: ["2018-01-06"])
    end

    it do
      expect { instance }.to raise_error(ArgumentError).
        with_message("Holidays cannot be extra working dates")
    end
  end

  context "when working date on working day" do
    let(:instance) do
      described_class.new(name: "test",
                          working_days: ["mon"],
                          extra_working_dates: ["Monday 26th Mar, 2018"])
    end

    it do
      expect { instance }.to raise_error(ArgumentError).
        with_message("Extra working dates cannot be on working days")
    end
  end

  # A set of examples that are supposed to work when given Date and Time
  # objects. The implementation slightly differs, so i's worth running the
  # tests for both Date *and* Time.
  shared_examples "common" do
    describe "#business_day?" do
      subject { calendar.business_day?(day) }

      let(:calendar) do
        described_class.new(name: "test",
                            holidays: ["9am, Tuesday 1st Jan, 2013"],
                            extra_working_dates: ["9am, Sunday 6th Jan, 2013"])
      end

      context "when given a business day" do
        let(:day) { date_class.parse("9am, Wednesday 2nd Jan, 2013") }

        it { is_expected.to be_truthy }
      end

      context "when given a non-business day" do
        let(:day) { date_class.parse("9am, Saturday 5th Jan, 2013") }

        it { is_expected.to be_falsey }
      end

      context "when given a business day that is a holiday" do
        let(:day) { date_class.parse("9am, Tuesday 1st Jan, 2013") }

        it { is_expected.to be_falsey }
      end

      context "when given a non-business day that is a working date" do
        let(:day) { date_class.parse("9am, Sunday 6th Jan, 2013") }

        it { is_expected.to be_truthy }
      end
    end

    describe "#working_day?" do
      subject { calendar.working_day?(day) }

      let(:calendar) do
        described_class.new(name: "test",
                            holidays: ["9am, Tuesday 1st Jan, 2013"],
                            extra_working_dates: ["9am, Sunday 6th Jan, 2013"])
      end

      context "when given a working day" do
        let(:day) { date_class.parse("9am, Wednesday 2nd Jan, 2013") }

        it { is_expected.to be_truthy }
      end

      context "when given a non-working day" do
        let(:day) { date_class.parse("9am, Saturday 5th Jan, 2013") }

        it { is_expected.to be_falsey }
      end

      context "when given a working day that is a holiday" do
        let(:day) { date_class.parse("9am, Tuesday 1st Jan, 2013") }

        it { is_expected.to be_truthy }
      end

      context "when given a non-business day that is a working date" do
        let(:day) { date_class.parse("9am, Sunday 6th Jan, 2013") }

        it { is_expected.to be_truthy }
      end
    end

    describe "#holiday?" do
      subject { calendar.holiday?(day) }

      let(:calendar) do
        described_class.new(name: "test",
                            holidays: ["9am, Tuesday 1st Jan, 2013"],
                            extra_working_dates: ["9am, Sunday 6th Jan, 2013"])
      end

      context "when given a working day that is not a holiday" do
        let(:day) { date_class.parse("9am, Wednesday 2nd Jan, 2013") }

        it { is_expected.to be_falsey }
      end

      context "when given a non-working day that is not a holiday day" do
        let(:day) { date_class.parse("9am, Saturday 5th Jan, 2013") }

        it { is_expected.to be_falsey }
      end

      context "when given a day that is a holiday" do
        let(:day) { date_class.parse("9am, Tuesday 1st Jan, 2013") }

        it { is_expected.to be_truthy }
      end

      context "when given a non-business day that is no a holiday" do
        let(:day) { date_class.parse("9am, Sunday 6th Jan, 2013") }

        it { is_expected.to be_falsey }
      end
    end

    describe "#roll_forward" do
      subject { calendar.roll_forward(date) }

      let(:calendar) do
        described_class.new(name: "test", holidays: ["Tuesday 1st Jan, 2013"])
      end

      context "given a business day" do
        let(:date) { date_class.parse("Wednesday 2nd Jan, 2013") }

        it { is_expected.to eq(date) }
      end

      context "given a non-business day" do
        context "with a business day following it" do
          let(:date) { date_class.parse("Tuesday 1st Jan, 2013") }

          it { is_expected.to eq(date + day_interval) }
        end

        context "followed by another non-business day" do
          let(:date) { date_class.parse("Saturday 5th Jan, 2013") }

          it { is_expected.to eq(date + (2 * day_interval)) }
        end
      end
    end

    describe "#roll_backward" do
      subject { calendar.roll_backward(date) }

      let(:calendar) do
        described_class.new(name: "test", holidays: ["Tuesday 1st Jan, 2013"])
      end

      context "given a business day" do
        let(:date) { date_class.parse("Wednesday 2nd Jan, 2013") }

        it { is_expected.to eq(date) }
      end

      context "given a non-business day" do
        context "with a business day preceeding it" do
          let(:date) { date_class.parse("Tuesday 1st Jan, 2013") }

          it { is_expected.to eq(date - day_interval) }
        end

        context "preceeded by another non-business day" do
          let(:date) { date_class.parse("Sunday 6th Jan, 2013") }

          it { is_expected.to eq(date - (2 * day_interval)) }
        end
      end
    end

    describe "#next_business_day" do
      subject { calendar.next_business_day(date) }

      let(:calendar) do
        described_class.new(name: "test", holidays: ["Tuesday 1st Jan, 2013"])
      end

      context "given a business day" do
        let(:date) { date_class.parse("Wednesday 2nd Jan, 2013") }

        it { is_expected.to eq(date + day_interval) }
      end

      context "given a non-business day" do
        context "with a business day following it" do
          let(:date) { date_class.parse("Tuesday 1st Jan, 2013") }

          it { is_expected.to eq(date + day_interval) }
        end

        context "followed by another non-business day" do
          let(:date) { date_class.parse("Saturday 5th Jan, 2013") }

          it { is_expected.to eq(date + (2 * day_interval)) }
        end
      end
    end

    describe "#previous_business_day" do
      subject { calendar.previous_business_day(date) }

      let(:calendar) do
        described_class.new(name: "test", holidays: ["Tuesday 1st Jan, 2013"])
      end

      context "given a business day" do
        let(:date) { date_class.parse("Thursday 3nd Jan, 2013") }

        it { is_expected.to eq(date - day_interval) }
      end

      context "given a non-business day" do
        context "with a business day before it" do
          let(:date) { date_class.parse("Tuesday 1st Jan, 2013") }

          it { is_expected.to eq(date - day_interval) }
        end

        context "preceeded by another non-business day" do
          let(:date) { date_class.parse("Sunday 6th Jan, 2013") }

          it { is_expected.to eq(date - (2 * day_interval)) }
        end
      end
    end

    describe "#add_business_days" do
      subject { calendar.add_business_days(date, delta) }

      let(:extra_working_dates) { [] }
      let(:calendar) do
        described_class.new(name: "test",
                            holidays: ["Tuesday 1st Jan, 2013"],
                            extra_working_dates: extra_working_dates)
      end
      let(:delta) { 2 }

      context "given a business day" do
        context "and a period that includes only business days" do
          let(:date) { date_class.parse("Wednesday 2nd Jan, 2013") }

          it { is_expected.to eq(date + (delta * day_interval)) }
        end

        context "and a period that includes a weekend" do
          let(:date) { date_class.parse("Friday 4th Jan, 2013") }

          it { is_expected.to eq(date + ((delta + 2) * day_interval)) }
        end

        context "and a period that includes a working date weekend" do
          let(:extra_working_dates) { ["Sunday 6th Jan, 2013"] }
          let(:date) { date_class.parse("Friday 4th Jan, 2013") }

          it { is_expected.to eq(date + ((delta + 1) * day_interval)) }
        end

        context "and a period that includes a holiday day" do
          let(:date) { date_class.parse("Monday 31st Dec, 2012") }

          it { is_expected.to eq(date + ((delta + 1) * day_interval)) }
        end
      end

      context "given a non-business day" do
        let(:date) { date_class.parse("Tuesday 1st Jan, 2013") }

        it { is_expected.to eq(date + ((delta + 1) * day_interval)) }
      end
    end

    describe "#subtract_business_days" do
      subject { calendar.subtract_business_days(date, delta) }

      let(:extra_working_dates) { [] }
      let(:calendar) do
        described_class.new(name: "test",
                            holidays: ["Thursday 3rd Jan, 2013"],
                            extra_working_dates: extra_working_dates)
      end
      let(:delta) { 2 }

      context "given a business day" do
        context "and a period that includes only business days" do
          let(:date) { date_class.parse("Wednesday 2nd Jan, 2013") }

          it { is_expected.to eq(date - (delta * day_interval)) }
        end

        context "and a period that includes a weekend" do
          let(:date) { date_class.parse("Monday 31st Dec, 2012") }

          it { is_expected.to eq(date - ((delta + 2) * day_interval)) }
        end

        context "and a period that includes a working date weekend" do
          let(:extra_working_dates) { ["Saturday 29th Dec, 2012"] }
          let(:date) { date_class.parse("Monday 31st Dec, 2012") }

          it { is_expected.to eq(date - ((delta + 1) * day_interval)) }
        end

        context "and a period that includes a holiday day" do
          let(:date) { date_class.parse("Friday 4th Jan, 2013") }

          it { is_expected.to eq(date - ((delta + 1) * day_interval)) }
        end
      end

      context "given a non-business day" do
        let(:date) { date_class.parse("Thursday 3rd Jan, 2013") }

        it { is_expected.to eq(date - ((delta + 1) * day_interval)) }
      end
    end

    describe "#business_days_between" do
      subject do
        calendar.business_days_between(date_class.parse(date_1),
                                       date_class.parse(date_2))
      end

      let(:holidays) do
        ["Wed 27/5/2014", "Thu 12/6/2014", "Wed 18/6/2014", "Fri 20/6/2014",
         "Sun 22/6/2014", "Fri 27/6/2014", "Thu 3/7/2014"]
      end
      let(:extra_working_dates) do
        ["Sun 1/6/2014", "Sat 28/6/2014", "Sat 5/7/2014"]
      end
      let(:calendar) do
        described_class.new(name: "test",
                            holidays: holidays,
                            extra_working_dates: extra_working_dates)
      end

      context "starting on a business day" do
        let(:date_1) { "Mon 2/6/2014" }

        context "ending on a business day" do
          context "including only business days" do
            let(:date_2) { "Thu 5/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including only business days & weekend days" do
            let(:date_2) { "Mon 9/6/2014" }

            it { is_expected.to eq(5) }
          end

          context "including only business days, weekend days & working date" do
            let(:date_1) { "Thu 29/5/2014" }
            let(:date_2) { "The 3/6/2014" }

            it { is_expected.to be(4) }
          end

          context "including only business days & holidays" do
            let(:date_1) { "Mon 9/6/2014" }
            let(:date_2) { "Fri 13/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Fri 13/6/2014" }

            it { is_expected.to eq(8) }
          end

          context "including business, weekend, hoilday days & working date" do
            let(:date_1) { "Thu 26/6/2014" }
            let(:date_2) { "The 1/7/2014" }

            it { is_expected.to be(3) }
          end
        end

        context "ending on a weekend day" do
          context "including only business days & weekend days" do
            let(:date_2) { "Sun 8/6/2014" }

            it { is_expected.to eq(5) }
          end

          context "including business & weekend days & working date" do
            let(:date_1) { "Thu 29/5/2014" }
            let(:date_2) { "Sun 3/6/2014" }

            it { is_expected.to eq(4) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Sat 14/6/2014" }

            it { is_expected.to eq(9) }
          end

          context "including business, weekend & holiday days & working date" do
            let(:date_1) { "Thu 26/6/2014" }
            let(:date_2) { "Tue 2/7/2014" }

            it { is_expected.to eq(4) }
          end
        end

        context "ending on a holiday" do
          context "including only business days & holidays" do
            let(:date_1) { "Mon 9/6/2014" }
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(8) }
          end

          context "including business, weekend, holiday days & business date" do
            let(:date_1) { "Wed 28/5/2014" }
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(11) }
          end
        end

        context "ending on a working date" do
          let(:date_1) { "Fri 4/7/2014" }

          context "including only business days & working date" do
            let(:date_2) { "Sat 5/7/2014" }

            it { is_expected.to eq(1) }
          end

          context "including business, weekend days & working date" do
            let(:date_2) { "Tue 8/7/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days, holidays & working date" do
            let(:date_1) { "Wed 25/6/2014" }
            let(:date_2) { "Tue 8/7/2014" }

            it { is_expected.to eq(8) }
          end
        end
      end

      context "starting on a weekend" do
        let(:date_1) { "Sat 7/6/2014" }

        context "ending on a business day" do
          context "including only business days & weekend days" do
            let(:date_2) { "Mon 9/6/2014" }

            it { is_expected.to eq(0) }
          end

          context "including business, weekend days & working date" do
            let(:date_1) { "Sat 31/5/2014" }
            let(:date_2) { "Tue 3/6/2014" }

            it { is_expected.to eq(2) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Fri 13/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend, holilday days & working date" do
            let(:date_1) { "Sat 31/5/2014" }
            let(:date_2) { "Fri 13/6/2014" }

            it { is_expected.to eq(8) }
          end
        end

        context "ending on a weekend day" do
          context "including only business days & weekend days" do
            let(:date_2) { "Sun 8/6/2014" }

            it { is_expected.to eq(0) }
          end

          context "including business, weekend days & working date" do
            let(:date_1) { "Sat 31/5/2014" }
            let(:date_2) { "Sun 8/6/2014" }

            it { is_expected.to be(5) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Sat 14/6/2014" }

            it { is_expected.to eq(4) }
          end

          context "including business, weekend, holiday days & working date" do
            let(:date_1) { "Sat 31/5/2014" }
            let(:date_2) { "Sun 14/6/2014" }

            it { is_expected.to be(9) }
          end
        end

        context "ending on a holiday" do
          context "including business, weekend days, and holidays" do
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days & working date" do
            let(:date_1) { "Sat 31/5/2014" }
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(8) }
          end
        end

        context "ending on a working date" do
          let(:date_1) { "Sat 31/5/2014" }

          context "including only weekend days & working date" do
            let(:date_2) { "Sat 2/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including business, weekend days & working date" do
            let(:date_2) { "Tue 4/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days, holidays & working date" do
            let(:date_2) { "Tue 13/6/2014" }

            it { is_expected.to eq(8) }
          end
        end
      end

      context "starting on a holiday" do
        let(:date_1) { "Thu 12/6/2014" }

        context "ending on a business day" do
          context "including only business days & holidays" do
            let(:date_2) { "Fri 13/6/2014" }

            it { is_expected.to eq(0) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Thu 19/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business, weekend days, holidays & working date" do
            let(:date_1) { "Fri 27/6/2014" }
            let(:date_2) { "Tue 1/7/2014" }

            it { is_expected.to eq(2) }
          end
        end

        context "ending on a weekend day" do
          context "including business, weekend days, and holidays" do
            let(:date_2) { "Sun 15/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including business, weekend days, holidays & working date" do
            let(:date_1) { "Fri 27/6/2014" }
            let(:date_2) { "Sun 29/6/2014" }

            it { is_expected.to eq(1) }
          end
        end

        context "ending on a holiday" do
          context "including only business days & holidays" do
            let(:date_1) { "Wed 18/6/2014" }
            let(:date_2) { "Fri 20/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including business, weekend days, and holidays" do
            let(:date_2) { "Wed 18/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including business/weekend days, holidays & working date" do
            let(:date_1) { "27/5/2014" }
            let(:date_2) { "Thu 12/6/2014" }

            it { is_expected.to eq(11) }
          end
        end

        context "ending on a working date" do
          let(:date_1) { "Sat 27/6/2014" }

          context "including only holiday & working date" do
            let(:date_2) { "Sat 29/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including holiday, weekend days & working date" do
            let(:date_2) { "Tue 30/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including business, weekend days, holidays & working date" do
            let(:date_2) { "Tue 2/7/2014" }

            it { is_expected.to eq(3) }
          end
        end
      end

      context "starting on a working date" do
        let(:date_1) { "Sun 1/6/2014" }

        context "ending on a working day" do
          context "including only working date & working day" do
            let(:date_2) { "Wed 4/6/2014" }

            it { is_expected.to eq(3) }
          end

          context "including working date, working & weekend days" do
            let(:date_2) { "Tue 10/6/2014" }

            it { is_expected.to eq(6) }
          end

          context "including working date, working & weekend days & holiday" do
            let(:date_2) { "Tue 13/6/2014" }

            it { is_expected.to eq(8) }
          end
        end

        context "ending on a weekend day" do
          let(:date_1) { "Sat 28/6/2014" }

          context "including only working date & weekend day" do
            let(:date_2) { "Sun 29/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including working date, weekend & working days" do
            let(:date_1) { "Sat 5/7/2014" }
            let(:date_2) { "Wed 9/7/2014" }

            it { is_expected.to eq(3) }
          end

          context "including working date, weekend & working days & holiday" do
            let(:date_2) { "Fri 4/7/2014" }

            it { is_expected.to eq(4) }
          end
        end

        context "ending on a holiday" do
          let(:date_1) { "Sat 28/6/2014" }

          context "including only working date & holiday" do
            let(:holidays) { ["Mon 2/6/2014"] }
            let(:date_1) { "Sun 1/6/2014" }
            let(:date_2) { "Mon 2/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including working date, holiday & weekend day" do
            let(:holidays) { ["Mon 30/6/2014"] }
            let(:date_2) { "Mon 30/6/2014" }

            it { is_expected.to eq(1) }
          end

          context "including working date, holiday, weekend & working days" do
            let(:date_2) { "Thu 3/7/2014" }

            it { is_expected.to eq(4) }
          end
        end

        context "ending on a working date" do
          context "including working dates, weekend & working days" do
            let(:date_1) { "Sat 28/6/2014" }
            let(:date_2) { "Sat 5/7/2014" }

            it { is_expected.to eq(4) }
          end
        end
      end

      context "if a calendar has a holiday on a non-working (weekend) day" do
        context "for a range less than a week long" do
          let(:date_1) { "Thu 19/6/2014" }
          let(:date_2) { "Tue 24/6/2014" }

          it { is_expected.to eq(2) }
        end

        context "for a range more than a week long" do
          let(:date_1) { "Mon 16/6/2014" }
          let(:date_2) { "Tue 24/6/2014" }

          it { is_expected.to eq(4) }
        end
      end
    end
  end

  context "(using Date objects)" do
    let(:date_class) { Date }
    let(:day_interval) { 1 }

    it_behaves_like "common"
  end

  context "(using Time objects)" do
    let(:date_class) { Time }
    let(:day_interval) { 3600 * 24 }

    it_behaves_like "common"
  end

  context "(using DateTime objects)" do
    let(:date_class) { DateTime }
    let(:day_interval) { 1 }

    it_behaves_like "common"
  end
end
